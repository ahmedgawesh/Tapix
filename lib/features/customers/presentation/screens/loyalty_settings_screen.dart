import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/widgets/inputs/select_all_on_focus.dart';
import '../../domain/repositories/loyalty_repository.dart';

/// Full-screen loyalty settings with tier management
class LoyaltySettingsScreen extends StatefulWidget {
  const LoyaltySettingsScreen({super.key});

  @override
  State<LoyaltySettingsScreen> createState() => _LoyaltySettingsScreenState();
}

class _LoyaltySettingsScreenState extends State<LoyaltySettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // General settings controllers
  final _pointValueCtrl = TextEditingController();
  final _minRedemptionCtrl = TextEditingController();
  final _maxPercentCtrl = TextEditingController();
  final _pointsPerUnitCtrl = TextEditingController();
  final _minSpendCtrl = TextEditingController();

  bool _isEnabled = true;
  bool _allowRedemption = true;
  bool _isLoading = true;
  bool _isSaving = false;
  DateTime? _businessBirthdayDate;
  LoyaltySettings? _currentSettings;
  List<LoyaltyTier> _tiers = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final repo = sl<LoyaltyRepository>();
      var settings = await repo.getLoyaltySettings();

      // Auto-create default settings if none exist
      if (settings == null) {
        final db = sl<AppDatabase>();
        await db.customStatement('''
          INSERT INTO loyalty_settings (
            points_per_currency_unit, min_spend_for_points,
            referral_bonus_points, signup_bonus_points, review_bonus_points,
            is_enabled, point_value_cents, min_redemption_points,
            max_redemption_percent_bps, allow_points_redemption,
            created_at, updated_at
          ) VALUES (1, 0, 100, 50, 10, 1, 1, 100, 5000, 1,
            datetime('now'), datetime('now'))
        ''');
        settings = await repo.getLoyaltySettings();
      }

      final tiers = await repo.getAllTiers();

      if (mounted) {
        setState(() {
          _currentSettings = settings;
          _tiers = tiers;
          if (settings != null) {
            _isEnabled = settings.isEnabled;
            _allowRedemption = settings.allowPointsRedemption;
            _businessBirthdayDate = settings.businessBirthdayDate;
            _pointValueCtrl.text = settings.pointValueCents.toString();
            _minRedemptionCtrl.text = settings.minRedemptionPoints.toString();
            _maxPercentCtrl.text =
                (settings.maxRedemptionPercentBps / 100).toStringAsFixed(0);
            _pointsPerUnitCtrl.text = settings.pointsPerCurrencyUnit.toString();
            _minSpendCtrl.text =
                (settings.minSpendForPoints / 100).toStringAsFixed(2);
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (_currentSettings == null) return;
    setState(() => _isSaving = true);

    try {
      final repo = sl<LoyaltyRepository>();
      final pointValueCents = int.tryParse(_pointValueCtrl.text) ?? 1;
      final minRedemptionPoints = int.tryParse(_minRedemptionCtrl.text) ?? 100;
      final maxPercent = int.tryParse(_maxPercentCtrl.text) ?? 50;
      final pointsPerUnit = int.tryParse(_pointsPerUnitCtrl.text) ?? 1;
      final minSpend = double.tryParse(_minSpendCtrl.text) ?? 0;
      final minSpendCents = (minSpend * 100).round();

      final updated = LoyaltySettings(
        id: _currentSettings!.id,
        pointsPerCurrencyUnit: pointsPerUnit,
        minSpendForPoints: minSpendCents,
        pointsExpiryDays: _currentSettings!.pointsExpiryDays,
        referralBonusPoints: _currentSettings!.referralBonusPoints,
        signupBonusPoints: _currentSettings!.signupBonusPoints,
        reviewBonusPoints: _currentSettings!.reviewBonusPoints,
        isEnabled: _isEnabled,
        pointValueCents: pointValueCents.clamp(1, 10000),
        minRedemptionPoints: minRedemptionPoints.clamp(0, 100000),
        maxRedemptionPercentBps: (maxPercent * 100).clamp(0, 10000),
        allowPointsRedemption: _allowRedemption,
        businessBirthdayDate: _businessBirthdayDate,
        createdAt: _currentSettings!.createdAt,
        updatedAt: DateTime.now(),
      );

      await repo.updateLoyaltySettings(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('customers.loyalty_settings_saved'.tr())),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showTierEditDialog([LoyaltyTier? tier]) async {
    final result = await showDialog<LoyaltyTier>(
      context: context,
      builder: (ctx) => _TierEditDialog(tier: tier),
    );

    if (result != null && mounted) {
      final repo = sl<LoyaltyRepository>();
      try {
        if (tier == null) {
          await repo.createTier(result);
        } else {
          await repo.updateTier(result);
        }
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteTier(LoyaltyTier tier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('customers.loyalty_delete_tier_title'.tr()),
        content: Text('customers.loyalty_delete_tier_confirm'.tr(args: [tier.name])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final repo = sl<LoyaltyRepository>();
      try {
        await repo.deleteTier(tier.id);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('customers.loyalty_tier_deleted'.tr())),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pointValueCtrl.dispose();
    _minRedemptionCtrl.dispose();
    _maxPercentCtrl.dispose();
    _pointsPerUnitCtrl.dispose();
    _minSpendCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text('customers.loyalty_settings'.tr()),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(LucideIcons.settings),
              text: 'customers.loyalty_general_settings'.tr(),
            ),
            Tab(
              icon: const Icon(LucideIcons.layers),
              text: 'customers.loyalty_tiers'.tr(),
            ),
          ],
        ),
        actions: [
          if (!_isLoading && _currentSettings != null)
            IconButton(
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.save),
              onPressed: _isSaving ? null : _saveSettings,
              tooltip: 'common.save'.tr(),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildGeneralSettingsTab(theme, cs),
                _buildTiersTab(theme, cs),
              ],
            ),
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton.extended(
              onPressed: () => _showTierEditDialog(),
              icon: const Icon(LucideIcons.plus),
              label: Text('customers.loyalty_add_tier'.tr()),
            )
          : null,
    );
  }

  Widget _buildGeneralSettingsTab(ThemeData theme, ColorScheme cs) {
    final currencyService = sl<CurrencyService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Master toggle card
          Card(
            child: SwitchListTile(
              value: _isEnabled,
              onChanged: (v) => setState(() => _isEnabled = v),
              title: Text('customers.loyalty_enabled'.tr()),
              subtitle: Text('customers.loyalty_enabled_hint'.tr()),
              secondary: Icon(
                _isEnabled ? LucideIcons.toggleRight : LucideIcons.toggleLeft,
                color: _isEnabled ? Colors.deepPurple : cs.outline,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Earning section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.coins, color: Colors.amber[700]),
                      const SizedBox(width: 8),
                      Text(
                        'customers.loyalty_earning_settings'.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pointsPerUnitCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onTap: () => selectAllText(_pointsPerUnitCtrl),
                    decoration: InputDecoration(
                      labelText: 'customers.loyalty_points_per_unit'.tr(),
                      helperText: 'customers.loyalty_points_per_unit_hint'.tr(),
                      prefixIcon: const Icon(LucideIcons.star),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _minSpendCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onTap: () => selectAllText(_minSpendCtrl),
                    decoration: InputDecoration(
                      labelText: 'customers.loyalty_min_spend'.tr(),
                      helperText: 'customers.loyalty_min_spend_hint'.tr(),
                      prefixIcon: const Icon(LucideIcons.shoppingCart),
                      suffixText: currencyService.currencySymbol,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Redemption section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.gift, color: Colors.green[700]),
                      const SizedBox(width: 8),
                      Text(
                        'customers.loyalty_redemption_settings'.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    value: _allowRedemption,
                    onChanged: (v) => setState(() => _allowRedemption = v),
                    title: Text('customers.loyalty_allow_redemption'.tr()),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pointValueCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onTap: () => selectAllText(_pointValueCtrl),
                    decoration: InputDecoration(
                      labelText: 'customers.loyalty_point_value'.tr(),
                      helperText: 'customers.loyalty_point_value_hint'.tr(),
                      prefixIcon: const Icon(LucideIcons.dollarSign),
                      suffixText: 'customers.loyalty_cents'.tr(),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _minRedemptionCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onTap: () => selectAllText(_minRedemptionCtrl),
                    decoration: InputDecoration(
                      labelText: 'customers.loyalty_min_redemption'.tr(),
                      helperText: 'customers.loyalty_min_redemption_hint'.tr(),
                      prefixIcon: const Icon(LucideIcons.arrowDownCircle),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _maxPercentCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onTap: () => selectAllText(_maxPercentCtrl),
                    decoration: InputDecoration(
                      labelText: 'customers.loyalty_max_percent'.tr(),
                      helperText: 'customers.loyalty_max_percent_hint'.tr(),
                      prefixIcon: const Icon(LucideIcons.percent),
                      suffixText: '%',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Business Birthday section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.cake, color: Colors.pink[400]),
                      const SizedBox(width: 8),
                      Text(
                        'customers.business_birthday'.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'customers.business_birthday_hint'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.outline,
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _businessBirthdayDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) {
                        setState(() => _businessBirthdayDate = date);
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.outline),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.calendar, color: cs.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _businessBirthdayDate != null
                                  ? '${_businessBirthdayDate!.day}/${_businessBirthdayDate!.month}'
                                  : 'customers.select_birthday_date'.tr(),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: _businessBirthdayDate != null
                                    ? null
                                    : cs.outline,
                              ),
                            ),
                          ),
                          if (_businessBirthdayDate != null)
                            IconButton(
                              icon: Icon(LucideIcons.x, color: cs.error),
                              onPressed: () =>
                                  setState(() => _businessBirthdayDate = null),
                              tooltip: 'common.clear'.tr(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTiersTab(ThemeData theme, ColorScheme cs) {
    if (_tiers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.layers, size: 64, color: cs.outline),
            const SizedBox(height: 16),
            Text(
              'customers.loyalty_no_tiers'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(color: cs.outline),
            ),
            const SizedBox(height: 8),
            Text(
              'customers.loyalty_no_tiers_hint'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tiers.length,
      onReorder: (oldIndex, newIndex) {
        // TODO: Implement reorder
      },
      itemBuilder: (context, index) {
        final tier = _tiers[index];
        return _TierCard(
          key: ValueKey(tier.id),
          tier: tier,
          onEdit: () => _showTierEditDialog(tier),
          onDelete: () => _deleteTier(tier),
        );
      },
    );
  }
}

/// Card widget for displaying a loyalty tier
class _TierCard extends StatelessWidget {
  final LoyaltyTier tier;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TierCard({
    super.key,
    required this.tier,
    required this.onEdit,
    required this.onDelete,
  });

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.grey;
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tierColor = _parseColor(tier.color);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: tierColor.withValues(alpha: 0.2),
          child: Icon(LucideIcons.award, color: tierColor),
        ),
        title: Text(
          tier.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: tierColor,
          ),
        ),
        subtitle: Text(
          'customers.loyalty_tier_points_range'.tr(args: [
            tier.minPoints.toString(),
            tier.maxPoints?.toString() ?? '∞',
          ]),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(LucideIcons.pencil),
              onPressed: onEdit,
              tooltip: 'common.edit'.tr(),
            ),
            IconButton(
              icon: Icon(LucideIcons.trash2, color: theme.colorScheme.error),
              onPressed: onDelete,
              tooltip: 'common.delete'.tr(),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBenefitRow(
                  context,
                  LucideIcons.x,
                  'customers.loyalty_points_multiplier'.tr(),
                  '${tier.pointsMultiplier}x',
                  tier.pointsMultiplier > 1.0,
                ),
                _buildBenefitRow(
                  context,
                  LucideIcons.percent,
                  'customers.loyalty_discount'.tr(),
                  '${tier.discountPercent.toStringAsFixed(0)}%',
                  tier.discountPercent > 0,
                ),
                _buildBenefitRow(
                  context,
                  LucideIcons.truck,
                  'customers.loyalty_free_shipping'.tr(),
                  tier.freeShipping ? '✓' : '✗',
                  tier.freeShipping,
                ),
                _buildBenefitRow(
                  context,
                  LucideIcons.headphones,
                  'customers.loyalty_priority_support'.tr(),
                  tier.prioritySupport ? '✓' : '✗',
                  tier.prioritySupport,
                ),
                _buildBenefitRow(
                  context,
                  LucideIcons.clock,
                  'customers.loyalty_early_access'.tr(),
                  '${tier.earlyAccessDays} ${'common.days'.tr()}',
                  tier.earlyAccessDays > 0,
                ),
                _buildBenefitRow(
                  context,
                  LucideIcons.gift,
                  'customers.loyalty_birthday_bonus'.tr(),
                  tier.birthdayBonus
                      ? (tier.birthdayBonusPoints > 0
                          ? '+${tier.birthdayBonusPoints} pts'
                          : '${tier.birthdayDiscountPercent.toStringAsFixed(0)}%')
                      : '✗',
                  tier.birthdayBonus,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    bool isActive,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isActive ? cs.primary : cs.outline,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? null : cs.outline,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isActive ? cs.primary : cs.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog for editing a loyalty tier
class _TierEditDialog extends StatefulWidget {
  final LoyaltyTier? tier;

  const _TierEditDialog({this.tier});

  @override
  State<_TierEditDialog> createState() => _TierEditDialogState();
}

class _TierEditDialogState extends State<_TierEditDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _nameArCtrl = TextEditingController();
  final _nameFrCtrl = TextEditingController();
  final _minPointsCtrl = TextEditingController();
  final _maxPointsCtrl = TextEditingController();
  final _multiplierCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _earlyAccessCtrl = TextEditingController();
  final _birthdayPointsCtrl = TextEditingController();
  final _birthdayDiscountCtrl = TextEditingController();

  bool _freeShipping = false;
  bool _prioritySupport = false;
  bool _exclusiveOffers = false;
  bool _birthdayBonus = false;
  String _selectedColor = '#CD7F32';

  final List<String> _colorOptions = [
    '#CD7F32', // Bronze
    '#C0C0C0', // Silver
    '#FFD700', // Gold
    '#9B59B6', // Purple
    '#3498DB', // Blue
    '#E74C3C', // Red
    '#2ECC71', // Green
    '#F39C12', // Orange
  ];

  @override
  void initState() {
    super.initState();
    final tier = widget.tier;
    if (tier != null) {
      _nameCtrl.text = tier.name;
      _nameArCtrl.text = tier.nameAr ?? '';
      _nameFrCtrl.text = tier.nameFr ?? '';
      _minPointsCtrl.text = tier.minPoints.toString();
      _maxPointsCtrl.text = tier.maxPoints?.toString() ?? '';
      _multiplierCtrl.text = tier.pointsMultiplier.toString();
      _discountCtrl.text = tier.discountPercent.toString();
      _earlyAccessCtrl.text = tier.earlyAccessDays.toString();
      _birthdayPointsCtrl.text = tier.birthdayBonusPoints.toString();
      _birthdayDiscountCtrl.text = tier.birthdayDiscountPercent.toStringAsFixed(0);
      _freeShipping = tier.freeShipping;
      _prioritySupport = tier.prioritySupport;
      _exclusiveOffers = tier.exclusiveOffers;
      _birthdayBonus = tier.birthdayBonus;
      _selectedColor = tier.color;
    } else {
      _minPointsCtrl.text = '0';
      _multiplierCtrl.text = '1.0';
      _discountCtrl.text = '0';
      _earlyAccessCtrl.text = '0';
      _birthdayPointsCtrl.text = '0';
      _birthdayDiscountCtrl.text = '0';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameArCtrl.dispose();
    _nameFrCtrl.dispose();
    _minPointsCtrl.dispose();
    _maxPointsCtrl.dispose();
    _multiplierCtrl.dispose();
    _discountCtrl.dispose();
    _earlyAccessCtrl.dispose();
    _birthdayPointsCtrl.dispose();
    _birthdayDiscountCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final tier = LoyaltyTier(
      id: widget.tier?.id ?? 0,
      name: _nameCtrl.text.trim(),
      nameAr: _nameArCtrl.text.trim().isEmpty ? null : _nameArCtrl.text.trim(),
      nameFr: _nameFrCtrl.text.trim().isEmpty ? null : _nameFrCtrl.text.trim(),
      minPoints: int.tryParse(_minPointsCtrl.text) ?? 0,
      maxPoints: _maxPointsCtrl.text.isEmpty
          ? null
          : int.tryParse(_maxPointsCtrl.text),
      pointsMultiplier: double.tryParse(_multiplierCtrl.text) ?? 1.0,
      discountPercent: double.tryParse(_discountCtrl.text) ?? 0.0,
      freeShipping: _freeShipping,
      freeShippingMinOrderCents: null,
      prioritySupport: _prioritySupport,
      earlyAccessDays: int.tryParse(_earlyAccessCtrl.text) ?? 0,
      exclusiveOffers: _exclusiveOffers,
      birthdayBonus: _birthdayBonus,
      birthdayBonusPoints: int.tryParse(_birthdayPointsCtrl.text) ?? 0,
      birthdayDiscountPercent: double.tryParse(_birthdayDiscountCtrl.text) ?? 0.0,
      color: _selectedColor,
      icon: null,
      badgeText: null,
      sortOrder: widget.tier?.sortOrder ?? 0,
      isActive: true,
      createdAt: widget.tier?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    Navigator.pop(context, tier);
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.tier != null;

    return AlertDialog(
      title: Text(
        isEditing
            ? 'customers.loyalty_edit_tier'.tr()
            : 'customers.loyalty_add_tier'.tr(),
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name fields
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'customers.loyalty_tier_name'.tr(),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameArCtrl,
                        decoration: InputDecoration(
                          labelText: 'customers.loyalty_tier_name_ar'.tr(),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _nameFrCtrl,
                        decoration: InputDecoration(
                          labelText: 'customers.loyalty_tier_name_fr'.tr(),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Color picker
                Text(
                  'customers.loyalty_tier_color'.tr(),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _colorOptions.map((color) {
                    final isSelected = _selectedColor == color;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedColor = color),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _parseColor(color),
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Colors.black, width: 3)
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white, size: 20)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Points range
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minPointsCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onTap: () => selectAllText(_minPointsCtrl),
                        decoration: InputDecoration(
                          labelText: 'customers.loyalty_min_points'.tr(),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _maxPointsCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onTap: () => selectAllText(_maxPointsCtrl),
                        decoration: InputDecoration(
                          labelText: 'customers.loyalty_max_points'.tr(),
                          hintText: '∞',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Benefits
                Text(
                  'customers.loyalty_tier_benefits'.tr(),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _multiplierCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        onTap: () => selectAllText(_multiplierCtrl),
                        decoration: InputDecoration(
                          labelText: 'customers.loyalty_points_multiplier'.tr(),
                          suffixText: 'x',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _discountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onTap: () => selectAllText(_discountCtrl),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        decoration: InputDecoration(
                          labelText: 'customers.loyalty_bonus_points'.tr(),
                          suffixText: '%',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          helperText: 'customers.loyalty_bonus_points_hint'.tr(),
                          helperMaxLines: 3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                CheckboxListTile(
                  value: _freeShipping,
                  onChanged: (v) => setState(() => _freeShipping = v ?? false),
                  title: Text('customers.loyalty_free_shipping'.tr()),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                CheckboxListTile(
                  value: _prioritySupport,
                  onChanged: (v) => setState(() => _prioritySupport = v ?? false),
                  title: Text('customers.loyalty_priority_support'.tr()),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                CheckboxListTile(
                  value: _exclusiveOffers,
                  onChanged: (v) => setState(() => _exclusiveOffers = v ?? false),
                  title: Text('customers.loyalty_exclusive_offers'.tr()),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                const SizedBox(height: 8),

                TextField(
                  controller: _earlyAccessCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onTap: () => selectAllText(_earlyAccessCtrl),
                  decoration: InputDecoration(
                    labelText: 'customers.loyalty_early_access'.tr(),
                    suffixText: 'common.days'.tr(),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                CheckboxListTile(
                  value: _birthdayBonus,
                  onChanged: (v) => setState(() => _birthdayBonus = v ?? false),
                  title: Text('customers.loyalty_birthday_bonus'.tr()),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                if (_birthdayBonus) ...[
                  const SizedBox(height: 4),
                  Text(
                    'customers.loyalty_birthday_hint'.tr(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _birthdayPointsCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onTap: () => selectAllText(_birthdayPointsCtrl),
                          decoration: InputDecoration(
                            labelText: 'customers.loyalty_birthday_points'.tr(),
                            border: const OutlineInputBorder(),
                            isDense: true,
                            helperText: 'customers.birthday_points_hint'.tr(),
                            helperMaxLines: 2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _birthdayDiscountCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onTap: () => selectAllText(_birthdayDiscountCtrl),
                          decoration: InputDecoration(
                            labelText: 'customers.loyalty_birthday_discount'.tr(),
                            suffixText: '%',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            helperText: 'customers.birthday_discount_hint'.tr(),
                            helperMaxLines: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _save,
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}
