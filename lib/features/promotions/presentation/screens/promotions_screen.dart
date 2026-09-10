import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/database/app_database.dart' hide PromotionScope;
import '../../../../core/database/daos/product_dao.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/money/money_input_parser.dart';
import '../../../../core/promotions/promotion_engine.dart';
import '../../../../core/promotions/promotion_repository.dart';
import '../../../../core/promotions/promotion_sale_snapshot.dart';
import '../../../../core/services/feature_gate_service.dart';
import '../../../auth/auth.dart';
import '../../../products/domain/entities/product_color_entity.dart' as domain;
import '../../../products/domain/entities/product_variant_entity.dart'
    as domain;
import '../../../products/domain/entities/size_entity.dart' as domain;
import '../../../products/domain/repositories/product_variant_repository.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';

class PromotionsScreen extends StatelessWidget {
  const PromotionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsBloc>().state.settings;
    final promotionsEnabled = sl<FeatureGateService>().isEnabled(
      AppFeature.promotions,
      settingEnabled: settings.enablePromotions,
    );
    final auth = context.watch<AuthBloc>().state;
    final user = auth is AuthAuthenticated ? auth.user : null;
    final canManage = sl<PermissionService>().hasPermission(
      user,
      Permissions.manageDiscounts,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('promotions.title'.tr()),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => context.push('/reports/promotions'),
            tooltip: 'promotions.report.title'.tr(),
            icon: const Icon(LucideIcons.chartNoAxesColumn),
          ),
        ],
      ),
      body: !promotionsEnabled
          ? _DisabledPromotions(onOpenSettings: () => context.go('/settings'))
          : StreamBuilder<List<Promotion>>(
              stream: sl<PromotionRepository>().watchAll(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _MessageState(
                    icon: LucideIcons.triangleAlert,
                    message: 'promotions.errors.load'.tr(),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final promotions = snapshot.data!;
                if (promotions.isEmpty) {
                  return _MessageState(
                    icon: LucideIcons.tags,
                    message: 'promotions.empty'.tr(),
                    action: canManage
                        ? FilledButton.icon(
                            onPressed: () => _openCreate(context, user?.id),
                            icon: const Icon(LucideIcons.plus),
                            label: Text('promotions.add'.tr()),
                          )
                        : null,
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth >= 1000
                        ? 960.0
                        : constraints.maxWidth;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: width,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: promotions.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) => _PromotionCard(
                            key: ValueKey<int>(promotions[index].id),
                            promotion: promotions[index],
                            canManage: canManage,
                            userId: user?.id,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: promotionsEnabled && canManage
          ? FloatingActionButton.extended(
              onPressed: () => _openCreate(context, user?.id),
              icon: const Icon(LucideIcons.plus),
              label: Text('promotions.add'.tr()),
            )
          : null,
    );
  }

  Future<void> _openCreate(BuildContext context, int? userId) async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PromotionFormDialog(userId: userId),
    );
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('promotions.created'.tr())));
    }
  }
}

class _PromotionCard extends StatefulWidget {
  final Promotion promotion;
  final bool canManage;
  final int? userId;

  const _PromotionCard({
    super.key,
    required this.promotion,
    required this.canManage,
    required this.userId,
  });

  @override
  State<_PromotionCard> createState() => _PromotionCardState();
}

class _PromotionCardState extends State<_PromotionCard> {
  bool _busy = false;

  Future<void> _showDetails() => showDialog<void>(
    context: context,
    builder: (_) => _PromotionDetailsDialog(promotion: widget.promotion),
  );

  Future<void> _edit() async {
    final rule = await sl<PromotionRepository>().loadRule(widget.promotion.id);
    if (rule == null || !mounted) return;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PromotionFormDialog(
        userId: widget.userId,
        sourcePromotionId: widget.promotion.id,
        initialRule: rule,
      ),
    );
  }

  Future<void> _duplicate() async {
    setState(() => _busy = true);
    try {
      await sl<PromotionRepository>().duplicate(
        widget.promotion.id,
        userId: widget.userId,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('promotions.duplicated'.tr())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setActive(bool active) async {
    setState(() => _busy = true);
    try {
      await sl<PromotionRepository>().setActive(
        widget.promotion.id,
        active,
        userId: widget.userId,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('promotions.errors.activate'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('promotions.archive'.tr()),
        content: Text('promotions.archive_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('promotions.archive'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await sl<PromotionRepository>().archive(
        widget.promotion.id,
        userId: widget.userId,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteUnused() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('promotions.delete'.tr()),
        content: Text('promotions.delete_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(LucideIcons.trash2),
            label: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await sl<PromotionRepository>().deleteUnused(
        widget.promotion.id,
        userId: widget.userId,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('promotions.deleted'.tr())));
      }
    } on StateError catch (error) {
      if (!mounted) return;
      final message = error.message == 'promotion_used'
          ? 'promotions.errors.delete_used'.tr()
          : 'promotions.errors.delete'.tr();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('promotions.errors.delete'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.promotion;
    final active = row.status == 'active';
    final archived = row.status == 'archived';
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _showDetails,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: active
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  LucideIcons.badgePercent,
                  color: active ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${row.code} • ${'promotions.types.${row.promotionType}'.tr()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'promotions.status.${row.status}'.tr(),
                      style: TextStyle(
                        color: active
                            ? colors.primary
                            : colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (widget.canManage) ...[
                if (!archived) Switch(value: active, onChanged: _setActive),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') _edit();
                    if (value == 'duplicate') _duplicate();
                    if (value == 'archive') _archive();
                    if (value == 'delete') _deleteUnused();
                  },
                  itemBuilder: (_) => [
                    if (!active)
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('promotions.edit'.tr()),
                      ),
                    PopupMenuItem(
                      value: 'duplicate',
                      child: Text('promotions.duplicate'.tr()),
                    ),
                    if (!archived)
                      PopupMenuItem(
                        value: 'archive',
                        child: Text('promotions.archive'.tr()),
                      ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'promotions.delete'.tr(),
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PromotionDetailsDialog extends StatelessWidget {
  final Promotion promotion;

  const _PromotionDetailsDialog({required this.promotion});

  Future<
    ({
      PromotionRule? rule,
      List<String> items,
      List<PromotionCurrencyPerformance> performance,
    })
  >
  _load() async {
    final repository = sl<PromotionRepository>();
    final rule = await repository.loadRule(promotion.id);
    if (rule == null) {
      return (
        rule: null,
        items: const <String>[],
        performance: const <PromotionCurrencyPerformance>[],
      );
    }
    final variantRepository = sl<ProductVariantRepository>();
    final colors = await variantRepository.watchAllColors().first;
    final sizes = await variantRepository.watchAllSizes().first;
    final colorById = {for (final color in colors) color.id: color.name};
    final sizeById = {for (final size in sizes) size.id: size.name};
    final categories = await sl<ProductDao>().watchCategories().first;
    final categoryById = {
      for (final category in categories) category.id: category.name,
    };
    final items = <String>[];
    for (final scope in rule.qualifierScopes.where((row) => !row.excluded)) {
      switch (scope.type) {
        case PromotionScopeType.product:
          final product = await sl<ProductDao>().getProductById(
            scope.targetId!,
          );
          if (product != null) {
            items.add(
              _componentLabel(
                product.name,
                scope.requiredQuantity,
                product.measurementType,
              ),
            );
          }
        case PromotionScopeType.variant:
          final variant = await variantRepository.getVariantById(
            scope.targetId!,
          );
          if (variant != null) {
            final product = await sl<ProductDao>().getProductById(
              variant.productId,
            );
            final details = <String>[
              if (variant.sku?.trim().isNotEmpty == true) variant.sku!.trim(),
              if (variant.colorId != null && colorById[variant.colorId] != null)
                colorById[variant.colorId!]!,
              if (variant.sizeId != null && sizeById[variant.sizeId] != null)
                sizeById[variant.sizeId!]!,
            ];
            items.add(
              _componentLabel(
                '${product?.name ?? 'promotions.details.unknown_product'.tr()}${details.isEmpty ? '' : ' (${details.join(' / ')})'}',
                scope.requiredQuantity,
                product?.measurementType ?? 'piece',
              ),
            );
          }
        case PromotionScopeType.category:
          items.add(
            categoryById[scope.targetId] ?? 'promotions.details.category'.tr(),
          );
        case PromotionScopeType.all:
          items.add('promotions.details.all_products'.tr());
      }
    }
    final performance = await repository.loadPerformance(promotion.id);
    return (rule: rule, items: items, performance: performance);
  }

  String _componentLabel(String name, int? quantity, String measurementType) {
    if (quantity == null) return name;
    return '$name — ${localizedQuantity(quantity, measurementType)}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(promotion.name),
      content: SizedBox(
        width: 560,
        child:
            FutureBuilder<
              ({
                PromotionRule? rule,
                List<String> items,
                List<PromotionCurrencyPerformance> performance,
              })
            >(
              future: _load(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rule = snapshot.data!.rule;
                if (rule == null) return Text('promotions.errors.load'.tr());
                final composed = rule.qualifierScopes.any(
                  (scope) => scope.isRequiredComponent,
                );
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _detailRow(
                        context,
                        'promotions.details.code'.tr(),
                        rule.code,
                      ),
                      _detailRow(
                        context,
                        'promotions.details.version'.tr(),
                        '${rule.version}',
                      ),
                      _detailRow(
                        context,
                        'promotions.details.type'.tr(),
                        'promotions.types.${_promotionTypeKey(rule.type)}'.tr(),
                      ),
                      _detailRow(
                        context,
                        'promotions.details.price_mode'.tr(),
                        'promotions.form.price_modes.${rule.priceMode}'.tr(),
                      ),
                      _detailRow(
                        context,
                        'promotions.details.reward'.tr(),
                        _rewardLabel(rule),
                      ),
                      _detailRow(
                        context,
                        'promotions.details.concurrency'.tr(),
                        'promotions.form.concurrency_modes.${rule.concurrencyMode.name}'
                            .tr(),
                      ),
                      _detailRow(
                        context,
                        'promotions.details.priority'.tr(),
                        '${rule.priority}',
                      ),
                      _detailRow(
                        context,
                        'promotions.details.max_applications'.tr(),
                        rule.maxApplicationsPerTransaction?.toString() ??
                            'promotions.form.unlimited'.tr(),
                      ),
                      _detailRow(
                        context,
                        'promotions.details.manual_combination'.tr(),
                        rule.allowManualDiscountCombination
                            ? 'common.yes'.tr()
                            : 'common.no'.tr(),
                      ),
                      if (rule.startsAt != null)
                        _detailRow(
                          context,
                          'promotions.form.starts_at'.tr(),
                          DateFormat(
                            'dd/MM/yyyy',
                          ).add_jm().format(rule.startsAt!),
                        ),
                      if (rule.endsAt != null)
                        _detailRow(
                          context,
                          'promotions.form.ends_at'.tr(),
                          DateFormat(
                            'dd/MM/yyyy',
                          ).add_jm().format(rule.endsAt!),
                        ),
                      if (composed)
                        _detailRow(
                          context,
                          'promotions.details.composition'.tr(),
                          'promotions.details.composed'.tr(),
                        )
                      else if (rule.qualifierScopes
                              .where((scope) => !scope.excluded)
                              .length >
                          1)
                        _detailRow(
                          context,
                          'promotions.details.composition'.tr(),
                          'promotions.details.direct_any'.tr(),
                        )
                      else if (rule.minimumQuantity > 0)
                        _detailRow(
                          context,
                          'promotions.details.minimum_quantity'.tr(),
                          '${rule.minimumQuantity}',
                        ),
                      const SizedBox(height: 14),
                      Text(
                        'promotions.details.eligible_items'.tr(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...snapshot.data!.items.map(
                        (item) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            LucideIcons.packageCheck,
                            size: 18,
                          ),
                          title: Text(item),
                        ),
                      ),
                      const Divider(height: 28),
                      Text(
                        'promotions.performance.title'.tr(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (snapshot.data!.performance.isEmpty)
                        Text(
                          'promotions.performance.empty'.tr(),
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        ...snapshot.data!.performance.map(
                          (performance) => Card(
                            elevation: 0,
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                children: [
                                  _detailRow(
                                    context,
                                    'promotions.performance.transactions'.tr(),
                                    '${performance.transactionCount}',
                                  ),
                                  _detailRow(
                                    context,
                                    'promotions.performance.applications'.tr(),
                                    '${performance.applicationCount}',
                                  ),
                                  _detailRow(
                                    context,
                                    'promotions.performance.discount'.tr(),
                                    _moneyLabel(
                                      performance.discountCents,
                                      performance.currencySymbol,
                                      performance.currencyCode,
                                    ),
                                  ),
                                  _detailRow(
                                    context,
                                    'promotions.performance.net_sales'.tr(),
                                    _moneyLabel(
                                      performance.netSalesCents,
                                      performance.currencySymbol,
                                      performance.currencyCode,
                                    ),
                                  ),
                                  _detailRow(
                                    context,
                                    'promotions.performance.cost'.tr(),
                                    _moneyLabel(
                                      performance.costCents,
                                      performance.currencySymbol,
                                      performance.currencyCode,
                                    ),
                                  ),
                                  _detailRow(
                                    context,
                                    'promotions.performance.gross_profit'.tr(),
                                    _moneyLabel(
                                      performance.grossProfitCents,
                                      performance.currencySymbol,
                                      performance.currencyCode,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.close'.tr()),
        ),
      ],
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 145,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  String _moneyLabel(int cents, String symbol, String code) =>
      '$symbol${(cents / 100).toStringAsFixed(2)} $code';

  String _rewardLabel(PromotionRule rule) => switch (rule.rewardType) {
    PromotionRewardType.percentageOff => '${rule.percentBps / 100}%',
    PromotionRewardType.amountOff => '${(rule.amountOff?.cents ?? 0) / 100}',
    PromotionRewardType.fixedBundlePrice =>
      '${(rule.fixedBundlePrice?.cents ?? 0) / 100}',
    PromotionRewardType.freeQuantity => 'promotions.details.free_quantity'.tr(
      namedArgs: {'count': '${rule.rewardQuantity}'},
    ),
  };
}

String _promotionTypeKey(PromotionType type) => switch (type) {
  PromotionType.simple => 'simple',
  PromotionType.quantity => 'quantity',
  PromotionType.fixedBundle => 'fixed_bundle',
  PromotionType.buyXGetY => 'buy_x_get_y',
  PromotionType.threshold => 'threshold',
};

class _PromotionFormDialog extends StatefulWidget {
  final int? userId;
  final int? sourcePromotionId;
  final PromotionRule? initialRule;

  const _PromotionFormDialog({
    required this.userId,
    this.sourcePromotionId,
    this.initialRule,
  });

  @override
  State<_PromotionFormDialog> createState() => _PromotionFormDialogState();
}

class _PromotionFormDialogState extends State<_PromotionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _quantity;
  late final TextEditingController _rewardQuantity;
  late final TextEditingController _value;
  late final TextEditingController _minimumSpend;
  late final TextEditingController _priority;
  late final TextEditingController _maxApplications;
  final _search = TextEditingController();
  PromotionType _type = PromotionType.simple;
  String _priceMode = 'retail';
  String _rewardMode = 'percentage';
  final Set<int> _productIds = {};
  final Set<int> _variantIds = {};
  final Set<int> _categoryIds = {};
  bool _allProducts = true;
  bool _composedBundle = false;
  bool _saving = false;
  bool _allowManualDiscountCombination = false;
  PromotionConcurrencyMode _concurrencyMode =
      PromotionConcurrencyMode.bestPrice;
  DateTime? _startsAt;
  DateTime? _endsAt;
  String _query = '';

  int get _selectedItemCount => _productIds.length + _variantIds.length;

  @override
  void initState() {
    super.initState();
    final rule = widget.initialRule;
    _name = TextEditingController(text: rule?.name ?? '');
    _code = TextEditingController(
      text: rule?.code ?? 'OFFER-${DateTime.now().millisecondsSinceEpoch}',
    );
    _quantity = TextEditingController(text: '${rule?.minimumQuantity ?? 2}');
    _rewardQuantity = TextEditingController(
      text: '${rule?.rewardQuantity ?? 1}',
    );
    final rewardValue = switch (rule?.rewardType) {
      PromotionRewardType.percentageOff =>
        ((rule?.percentBps ?? 1000) / 100).toString(),
      PromotionRewardType.amountOff =>
        ((rule?.amountOff?.cents ?? 1000) / 100).toString(),
      PromotionRewardType.fixedBundlePrice =>
        ((rule?.fixedBundlePrice?.cents ?? 1000) / 100).toString(),
      _ => '10',
    };
    _value = TextEditingController(text: rewardValue);
    _minimumSpend = TextEditingController(
      text: ((rule?.minimumSpend?.cents ?? 10000) / 100).toString(),
    );
    _priority = TextEditingController(text: '${rule?.priority ?? 0}');
    _maxApplications = TextEditingController(
      text: rule?.maxApplicationsPerTransaction?.toString() ?? '',
    );
    if (rule != null) {
      _type = rule.type;
      _priceMode = rule.priceMode;
      _rewardMode = rule.rewardType == PromotionRewardType.amountOff
          ? 'amount'
          : 'percentage';
      _concurrencyMode = rule.concurrencyMode;
      _allowManualDiscountCombination = rule.allowManualDiscountCombination;
      _startsAt = rule.startsAt;
      _endsAt = rule.endsAt;
      final included = rule.qualifierScopes.where((scope) => !scope.excluded);
      _productIds.addAll(
        included
            .where((scope) => scope.type == PromotionScopeType.product)
            .map((scope) => scope.targetId!),
      );
      _variantIds.addAll(
        included
            .where((scope) => scope.type == PromotionScopeType.variant)
            .map((scope) => scope.targetId!),
      );
      _categoryIds.addAll(
        included
            .where((scope) => scope.type == PromotionScopeType.category)
            .map((scope) => scope.targetId!),
      );
      _allProducts = included.any(
        (scope) => scope.type == PromotionScopeType.all,
      );
      _composedBundle = included.any((scope) => scope.isRequiredComponent);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _quantity.dispose();
    _rewardQuantity.dispose();
    _value.dispose();
    _minimumSpend.dispose();
    _priority.dispose();
    _maxApplications.dispose();
    _search.dispose();
    super.dispose();
  }

  PromotionRewardType get _rewardType => switch (_type) {
    PromotionType.fixedBundle => PromotionRewardType.fixedBundlePrice,
    PromotionType.buyXGetY => PromotionRewardType.freeQuantity,
    _ =>
      _rewardMode == 'amount'
          ? PromotionRewardType.amountOff
          : PromotionRewardType.percentageOff,
  };

  int? _percentageBps() {
    final value = Decimal.tryParse(_value.text.trim().replaceAll(',', '.'));
    if (value == null || value <= Decimal.zero) return null;
    final bps = value * Decimal.fromInt(100);
    if (!bps.isInteger) return null;
    final result = bps.toBigInt().toInt();
    return result <= 10000 ? result : null;
  }

  int? _moneyCents() {
    final result = sl<MoneyInputParser>().parse(_value.text);
    return result.isValid && result.cents > 0 ? result.cents : null;
  }

  Future<void> _showPriorityHelp() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.circleHelp),
          const SizedBox(width: 8),
          Expanded(child: Text('promotions.form.priority_help_title'.tr())),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Text('promotions.form.priority_help_body'.tr()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('common.close'.tr()),
        ),
      ],
    ),
  );

  Widget _responsivePair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 480) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 12), second],
        );
      }
      return Row(
        children: [
          Expanded(child: first),
          const SizedBox(width: 12),
          Expanded(child: second),
        ],
      );
    },
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_allProducts &&
        _productIds.isEmpty &&
        _variantIds.isEmpty &&
        _categoryIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('promotions.validation.products'.tr())),
      );
      return;
    }
    final selectedItemCount = _selectedItemCount;
    if (_composedBundle && selectedItemCount < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('promotions.validation.bundle_items'.tr())),
      );
      return;
    }
    final percentage = _rewardType == PromotionRewardType.percentageOff
        ? _percentageBps()
        : null;
    final money =
        _rewardType == PromotionRewardType.percentageOff ||
            _rewardType == PromotionRewardType.freeQuantity
        ? null
        : _moneyCents();
    if ((_rewardType == PromotionRewardType.percentageOff &&
            percentage == null) ||
        ((_rewardType == PromotionRewardType.amountOff ||
                _rewardType == PromotionRewardType.fixedBundlePrice) &&
            money == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('promotions.validation.value'.tr())),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final effectiveType = _composedBundle && _type == PromotionType.simple
          ? PromotionType.quantity
          : _type;
      final draft = PromotionDraft(
        code: _code.text,
        name: _name.text,
        type: effectiveType,
        priceMode: _priceMode,
        rewardType: _rewardType,
        concurrencyMode: _concurrencyMode,
        productIds: _allProducts ? const [] : _productIds.toList(),
        variantIds: _allProducts ? const [] : _variantIds.toList(),
        categoryIds: _allProducts ? const [] : _categoryIds.toList(),
        requireEachSelectedItem: _composedBundle,
        minimumQuantity: _composedBundle
            ? selectedItemCount
            : int.tryParse(_quantity.text) ?? 0,
        rewardQuantity: int.tryParse(_rewardQuantity.text) ?? 0,
        percentBps: percentage ?? 0,
        amountCents: _rewardType == PromotionRewardType.amountOff
            ? money
            : null,
        fixedPriceCents: _rewardType == PromotionRewardType.fixedBundlePrice
            ? money
            : null,
        minimumSpendCents: _type == PromotionType.threshold
            ? sl<MoneyInputParser>().parseOrZero(_minimumSpend.text)
            : null,
        startsAt: _startsAt,
        endsAt: _endsAt,
        priority: int.tryParse(_priority.text) ?? 0,
        maxApplicationsPerTransaction: int.tryParse(_maxApplications.text),
        allowManualDiscountCombination: _allowManualDiscountCombination,
      );
      if (widget.sourcePromotionId == null) {
        await sl<PromotionRepository>().create(draft, userId: widget.userId);
      } else {
        await sl<PromotionRepository>().revise(
          widget.sourcePromotionId!,
          draft,
          userId: widget.userId,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on StateError catch (error) {
      if (!mounted) return;
      final duplicate = error.message == 'promotion_code_exists';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            duplicate
                ? 'promotions.validation.code_exists'.tr()
                : 'promotions.errors.save'.tr(),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('promotions.errors.save'.tr())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsQuantity =
        _type == PromotionType.quantity ||
        _type == PromotionType.fixedBundle ||
        _type == PromotionType.buyXGetY;
    final valueLabel = switch (_rewardType) {
      PromotionRewardType.percentageOff => 'promotions.form.percent'.tr(),
      PromotionRewardType.amountOff => 'promotions.form.amount'.tr(),
      PromotionRewardType.fixedBundlePrice =>
        'promotions.form.bundle_price'.tr(),
      PromotionRewardType.freeQuantity => '',
    };

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              ListTile(
                title: Text(
                  widget.sourcePromotionId == null
                      ? 'promotions.form.title'.tr()
                      : 'promotions.form.edit_title'.tr(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                trailing: IconButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(LucideIcons.x),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _name,
                        decoration: InputDecoration(
                          labelText: 'promotions.form.name'.tr(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'promotions.validation.required'.tr()
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _code,
                        decoration: InputDecoration(
                          labelText: 'promotions.form.code'.tr(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'promotions.validation.required'.tr()
                            : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<PromotionType>(
                        initialValue: _type,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'promotions.form.type'.tr(),
                        ),
                        items: PromotionType.values
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(
                                  'promotions.types.${_typeKey(type)}'.tr(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _type = value;
                              if (value == PromotionType.buyXGetY ||
                                  value == PromotionType.threshold) {
                                _composedBundle = false;
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<PromotionConcurrencyMode>(
                        initialValue: _concurrencyMode,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'promotions.form.concurrency'.tr(),
                        ),
                        items: PromotionConcurrencyMode.values
                            .map(
                              (mode) => DropdownMenuItem(
                                value: mode,
                                child: Text(
                                  'promotions.form.concurrency_modes.${mode.name}'
                                      .tr(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _concurrencyMode = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _responsivePair(
                        TextFormField(
                          controller: _priority,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'promotions.form.priority'.tr(),
                            suffixIcon: IconButton(
                              tooltip: 'promotions.form.priority_help_title'
                                  .tr(),
                              onPressed: _showPriorityHelp,
                              icon: const Icon(LucideIcons.circleHelp),
                            ),
                          ),
                        ),
                        TextFormField(
                          controller: _maxApplications,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'promotions.form.max_applications'.tr(),
                            hintText: 'promotions.form.unlimited'.tr(),
                          ),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'promotions.form.allow_manual_combination'.tr(),
                        ),
                        subtitle: Text(
                          'promotions.form.allow_manual_combination_desc'.tr(),
                        ),
                        value: _allowManualDiscountCombination,
                        onChanged: (value) => setState(
                          () => _allowManualDiscountCombination = value,
                        ),
                      ),
                      _responsivePair(
                        _DateTimeField(
                          label: 'promotions.form.starts_at'.tr(),
                          value: _startsAt,
                          onChanged: (value) =>
                              setState(() => _startsAt = value),
                        ),
                        _DateTimeField(
                          label: 'promotions.form.ends_at'.tr(),
                          value: _endsAt,
                          onChanged: (value) => setState(() => _endsAt = value),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _priceMode,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'promotions.form.price_mode'.tr(),
                        ),
                        items: const ['retail', 'wholesale', 'any']
                            .map(
                              (mode) => DropdownMenuItem(
                                value: mode,
                                child: Text(
                                  'promotions.form.price_modes.$mode'.tr(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _priceMode = value);
                          }
                        },
                      ),
                      if (_type != PromotionType.fixedBundle &&
                          _type != PromotionType.buyXGetY) ...[
                        const SizedBox(height: 12),
                        SegmentedButton<String>(
                          segments: [
                            ButtonSegment(
                              value: 'percentage',
                              label: Text('promotions.form.percentage'.tr()),
                            ),
                            ButtonSegment(
                              value: 'amount',
                              label: Text('promotions.form.fixed_amount'.tr()),
                            ),
                          ],
                          selected: {_rewardMode},
                          onSelectionChanged: (value) =>
                              setState(() => _rewardMode = value.first),
                        ),
                      ],
                      if (needsQuantity && !_composedBundle) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _quantity,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: _type == PromotionType.buyXGetY
                                ? 'promotions.form.buy_quantity'.tr()
                                : 'promotions.form.quantity'.tr(),
                          ),
                        ),
                      ],
                      if (_type == PromotionType.buyXGetY) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _rewardQuantity,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'promotions.form.free_quantity'.tr(),
                          ),
                        ),
                      ] else ...[
                        if (_type == PromotionType.threshold) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _minimumSpend,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'promotions.form.minimum_spend'.tr(),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _value,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(labelText: valueLabel),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('promotions.form.all_products'.tr()),
                        value: _allProducts,
                        onChanged: (value) => setState(() {
                          _allProducts = value;
                          if (value) {
                            _productIds.clear();
                            _variantIds.clear();
                            _categoryIds.clear();
                            _composedBundle = false;
                          }
                        }),
                      ),
                      if (!_allProducts &&
                          _categoryIds.isEmpty &&
                          (_type == PromotionType.simple ||
                              _type == PromotionType.quantity ||
                              _type == PromotionType.fixedBundle)) ...[
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('promotions.form.composed_bundle'.tr()),
                          subtitle: Text(
                            'promotions.form.composed_bundle_desc'.tr(),
                          ),
                          value: _composedBundle,
                          onChanged: (value) =>
                              setState(() => _composedBundle = value),
                        ),
                        if (_composedBundle)
                          Text(
                            'promotions.form.bundle_component_count'.tr(
                              namedArgs: {'count': '$_selectedItemCount'},
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (!_composedBundle && _selectedItemCount > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'promotions.form.direct_scope_desc'.tr(),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                            ),
                          ),
                      ],
                      if (!_allProducts) ...[
                        StreamBuilder<List<ProductCategory>>(
                          stream: sl<ProductDao>().watchCategories(),
                          builder: (context, snapshot) {
                            final categories = snapshot.data ?? const [];
                            if (categories.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('promotions.form.categories'.tr()),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: categories
                                      .map(
                                        (category) => FilterChip(
                                          label: Text(category.name),
                                          selected: _categoryIds.contains(
                                            category.id,
                                          ),
                                          onSelected: (selected) =>
                                              setState(() {
                                                if (selected) {
                                                  _categoryIds.add(category.id);
                                                  _composedBundle = false;
                                                } else {
                                                  _categoryIds.remove(
                                                    category.id,
                                                  );
                                                }
                                              }),
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
                                const SizedBox(height: 10),
                              ],
                            );
                          },
                        ),
                        TextField(
                          controller: _search,
                          onChanged: (value) => setState(() => _query = value),
                          decoration: InputDecoration(
                            labelText: 'promotions.form.search_products'.tr(),
                            prefixIcon: const Icon(LucideIcons.search),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 230,
                          child: _PromotionProductPicker(
                            query: _query,
                            selectedProductIds: _productIds,
                            selectedVariantIds: _variantIds,
                            onProductChanged: (productId, checked) =>
                                setState(() {
                                  if (checked) {
                                    _productIds.add(productId);
                                  } else {
                                    _productIds.remove(productId);
                                  }
                                }),
                            onVariantChanged: (variantId, checked) =>
                                setState(() {
                                  if (checked) {
                                    _variantIds.add(variantId);
                                  } else {
                                    _variantIds.remove(variantId);
                                  }
                                }),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: Text('common.cancel'.tr()),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(LucideIcons.save),
                      label: Text('common.save'.tr()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _typeKey(PromotionType type) => switch (type) {
    PromotionType.simple => 'simple',
    PromotionType.quantity => 'quantity',
    PromotionType.fixedBundle => 'fixed_bundle',
    PromotionType.buyXGetY => 'buy_x_get_y',
    PromotionType.threshold => 'threshold',
  };
}

class _PromotionProductPicker extends StatelessWidget {
  final String query;
  final Set<int> selectedProductIds;
  final Set<int> selectedVariantIds;
  final void Function(int productId, bool checked) onProductChanged;
  final void Function(int variantId, bool checked) onVariantChanged;

  const _PromotionProductPicker({
    required this.query,
    required this.selectedProductIds,
    required this.selectedVariantIds,
    required this.onProductChanged,
    required this.onVariantChanged,
  });

  @override
  Widget build(BuildContext context) {
    final variants = sl<ProductVariantRepository>();
    return StreamBuilder<List<Product>>(
      stream: sl<ProductDao>().watchAllProducts(),
      builder: (context, productsSnapshot) {
        if (!productsSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return StreamBuilder<List<domain.ProductVariant>>(
          stream: variants.watchAllVariants(),
          builder: (context, variantsSnapshot) {
            if (!variantsSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return StreamBuilder<List<domain.ProductColor>>(
              stream: variants.watchAllColors(),
              builder: (context, colorsSnapshot) {
                final colors = colorsSnapshot.data ?? const [];
                return StreamBuilder<List<domain.Size>>(
                  stream: variants.watchAllSizes(),
                  builder: (context, sizesSnapshot) {
                    final sizes = sizesSnapshot.data ?? const [];
                    return _buildList(
                      context,
                      products: productsSnapshot.data!,
                      variants: variantsSnapshot.data!,
                      colors: colors,
                      sizes: sizes,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildList(
    BuildContext context, {
    required List<Product> products,
    required List<domain.ProductVariant> variants,
    required List<domain.ProductColor> colors,
    required List<domain.Size> sizes,
  }) {
    final colorsById = {for (final color in colors) color.id: color};
    final sizesById = {for (final size in sizes) size.id: size};
    final variantsByProduct = <int, List<domain.ProductVariant>>{};
    for (final variant in variants.where((row) => row.isActive)) {
      variantsByProduct.putIfAbsent(variant.productId, () => []).add(variant);
    }

    final normalizedQuery = query.trim().toLowerCase();
    final visible =
        <({Product product, List<domain.ProductVariant> variants})>[];
    for (final product in products) {
      final allProductVariants = variantsByProduct[product.id] ?? const [];
      final dimensionalVariants = allProductVariants
          .where((row) => row.colorId != null || row.sizeId != null)
          .toList(growable: false);
      final selectableVariants = product.hasVariants
          ? (dimensionalVariants.isNotEmpty
                ? dimensionalVariants
                : allProductVariants)
          : allProductVariants;
      final productMatches =
          _contains(product.name, normalizedQuery) ||
          _contains(product.sku, normalizedQuery) ||
          _contains(product.barcode, normalizedQuery);
      final matchingVariants = normalizedQuery.isEmpty || productMatches
          ? selectableVariants
          : selectableVariants
                .where(
                  (variant) => _variantMatches(
                    variant,
                    normalizedQuery,
                    colorsById,
                    sizesById,
                  ),
                )
                .toList(growable: false);
      final simpleMatches =
          productMatches ||
          selectableVariants.any(
            (variant) => _variantMatches(
              variant,
              normalizedQuery,
              colorsById,
              sizesById,
            ),
          );

      if (product.hasVariants) {
        if (matchingVariants.isNotEmpty) {
          visible.add((product: product, variants: matchingVariants));
        }
      } else if (normalizedQuery.isEmpty || simpleMatches) {
        visible.add((product: product, variants: selectableVariants));
      }
    }

    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final group = visible[index];
        if (!group.product.hasVariants) {
          return _simpleProductTile(
            context,
            group.product,
            group.variants,
            colorsById,
          );
        }
        return _variantProductGroup(
          context,
          group.product,
          group.variants,
          colorsById,
          sizesById,
        );
      },
    );
  }

  Widget _simpleProductTile(
    BuildContext context,
    Product product,
    List<domain.ProductVariant> variants,
    Map<int, domain.ProductColor> colorsById,
  ) {
    final colorId = variants
        .where((row) => row.colorId != null)
        .map((row) => row.colorId)
        .firstOrNull;
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: _detailsWrap(
        context,
        identifier: product.sku ?? product.barcode ?? '—',
        stockQuantity: product.stockQuantity,
        measurementType: product.measurementType,
        colorHex: colorId == null ? null : colorsById[colorId]?.hexCode,
      ),
      value: selectedProductIds.contains(product.id),
      onChanged: (checked) => onProductChanged(product.id, checked == true),
    );
  }

  Widget _variantProductGroup(
    BuildContext context,
    Product product,
    List<domain.ProductVariant> productVariants,
    Map<int, domain.ProductColor> colorsById,
    Map<int, domain.Size> sizesById,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 4),
          color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
          child: Row(
            children: [
              Icon(LucideIcons.layers, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Text('${productVariants.length}'),
            ],
          ),
        ),
        for (final variant in productVariants)
          CheckboxListTile(
            dense: true,
            contentPadding: const EdgeInsetsDirectional.only(start: 18),
            title: Text(
              variant.sku ?? variant.barcode ?? '#${variant.id}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: _detailsWrap(
              context,
              identifier:
                  variant.barcode != null && variant.barcode != variant.sku
                  ? variant.barcode
                  : null,
              sizeName: variant.sizeId == null
                  ? null
                  : sizesById[variant.sizeId!]?.name,
              stockQuantity: variant.stockQuantity,
              measurementType: product.measurementType,
              colorHex: variant.colorId == null
                  ? null
                  : colorsById[variant.colorId!]?.hexCode,
            ),
            value: selectedVariantIds.contains(variant.id),
            onChanged: (checked) =>
                onVariantChanged(variant.id, checked == true),
          ),
      ],
    );
  }

  Widget _detailsWrap(
    BuildContext context, {
    String? identifier,
    String? sizeName,
    required int stockQuantity,
    required String measurementType,
    String? colorHex,
  }) {
    final color = _tryParsePromotionColor(colorHex);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (identifier != null && identifier.trim().isNotEmpty)
          Text(identifier),
        if (sizeName != null && sizeName.trim().isNotEmpty) Text(sizeName),
        Text(
          localizedQuantity(stockQuantity, measurementType),
          style: TextStyle(
            color: stockQuantity > 0
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (color != null)
          Semantics(
            label: 'colors.title'.tr(),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _variantMatches(
    domain.ProductVariant variant,
    String normalizedQuery,
    Map<int, domain.ProductColor> colorsById,
    Map<int, domain.Size> sizesById,
  ) {
    if (normalizedQuery.isEmpty) return true;
    return _contains(variant.sku, normalizedQuery) ||
        _contains(variant.barcode, normalizedQuery) ||
        _contains(
          variant.colorId == null ? null : colorsById[variant.colorId!]?.name,
          normalizedQuery,
        ) ||
        _contains(
          variant.sizeId == null ? null : sizesById[variant.sizeId!]?.name,
          normalizedQuery,
        );
  }

  bool _contains(String? value, String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    return value?.toLowerCase().contains(normalizedQuery) == true;
  }
}

class _DateTimeField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  const _DateTimeField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: value == null
          ? TimeOfDay.fromDateTime(now)
          : TimeOfDay.fromDateTime(value!),
    );
    if (time == null) return;
    onChanged(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? 'promotions.form.not_set'.tr()
        : DateFormat('dd/MM/yyyy').add_jm().format(value!);
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Expanded(
            child: InkWell(onTap: () => _pick(context), child: Text(text)),
          ),
          if (value != null)
            IconButton(
              tooltip: 'common.clear'.tr(),
              onPressed: () => onChanged(null),
              icon: const Icon(LucideIcons.x, size: 18),
            )
          else
            IconButton(
              onPressed: () => _pick(context),
              icon: const Icon(LucideIcons.calendarClock, size: 18),
            ),
        ],
      ),
    );
  }
}

Color? _tryParsePromotionColor(String? hex) {
  if (hex == null) return null;
  final cleaned = hex.trim().replaceFirst('#', '');
  if (cleaned.isEmpty) return null;
  final normalized = cleaned.length == 6 ? 'ff$cleaned' : cleaned;
  if (normalized.length != 8) return null;
  final value = int.tryParse(normalized, radix: 16);
  return value == null ? null : Color(value);
}

class _DisabledPromotions extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _DisabledPromotions({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) => _MessageState(
    icon: LucideIcons.badgePercent,
    message: 'promotions.disabled'.tr(),
    action: FilledButton(
      onPressed: onOpenSettings,
      child: Text('promotions.open_settings'.tr()),
    ),
  );
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;

  const _MessageState({required this.icon, required this.message, this.action});

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}
