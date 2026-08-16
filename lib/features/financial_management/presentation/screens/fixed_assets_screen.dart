import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/money/money_input_parser.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/fixed_asset_service.dart';
import '../../../accounting/presentation/utils/account_display_name.dart';

class FixedAssetsScreen extends StatefulWidget {
  const FixedAssetsScreen({super.key});

  @override
  State<FixedAssetsScreen> createState() => _FixedAssetsScreenState();
}

class _FixedAssetsScreenState extends State<FixedAssetsScreen> {
  final _service = sl<FixedAssetService>();
  final _currency = sl<CurrencyService>();
  late final Future<
    ({
      List<Account> assetAccounts,
      List<Account> fundingAccounts,
      int currencyId,
    })
  >
  _setup;

  @override
  void initState() {
    super.initState();
    _setup = _loadSetup();
  }

  Future<
    ({
      List<Account> assetAccounts,
      List<Account> fundingAccounts,
      int currencyId,
    })
  >
  _loadSetup() async {
    final values = await Future.wait([
      _service.getAssetAccounts(),
      _service.getFundingAccounts(),
      _service.getDefaultCurrencyId(),
    ]);
    return (
      assetAccounts: values[0] as List<Account>,
      fundingAccounts: values[1] as List<Account>,
      currencyId: values[2] as int,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('financial_management.fixed_assets'.tr()),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateDialog,
        icon: const Icon(Icons.add_business_outlined),
        label: Text('financial_management.asset_add'.tr()),
      ),
      body: StreamBuilder<List<FixedAsset>>(
        stream: _service.watchAssets(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(_message(snapshot.error!)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final assets = snapshot.data!;
          if (assets.isEmpty) {
            return _EmptyAssets(
              title: 'financial_management.asset_empty'.tr(),
              subtitle: 'financial_management.asset_empty_desc'.tr(),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: assets.length,
            itemBuilder: (_, index) => _AssetCard(
              asset: assets[index],
              service: _service,
              currency: _currency,
              onPostDepreciation: _postDepreciation,
              onVoidDepreciation: _voidDepreciation,
              onVoidAsset: _voidAsset,
            ),
          );
        },
      ),
    );
  }

  Future<void> _openCreateDialog() async {
    try {
      final setup = await _setup;
      if (!mounted) return;
      if (setup.assetAccounts.isEmpty || setup.fundingAccounts.isEmpty) {
        _showError('financial_management.asset_accounts_missing'.tr());
        return;
      }
      final result = await showDialog<FixedAssetAcquisitionResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _FixedAssetDialog(
          service: _service,
          assetAccounts: setup.assetAccounts,
          fundingAccounts: setup.fundingAccounts,
          currencyId: setup.currencyId,
        ),
      );
      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'financial_management.asset_saved'.tr(args: [result.assetNumber]),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) _showError(_message(error));
    }
  }

  Future<void> _postDepreciation(FixedAssetSummary summary) async {
    try {
      final result = await _service.postNextDepreciation(
        assetId: summary.asset.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'financial_management.depreciation_saved'.tr(
                args: [_currency.formatCents(result.amountCents)],
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) _showError(_message(error));
    }
  }

  Future<void> _voidDepreciation(FixedAssetSummary summary) async {
    if (summary.latestDepreciationId == null) return;
    final reason = await _askVoidReason();
    if (reason == null || !mounted) return;
    try {
      await _service.voidLatestDepreciation(
        depreciationId: summary.latestDepreciationId!,
        reason: reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('financial_management.void_success'.tr())),
        );
      }
    } catch (error) {
      if (mounted) _showError(_message(error));
    }
  }

  Future<void> _voidAsset(FixedAssetSummary summary) async {
    final reason = await _askVoidReason();
    if (reason == null || !mounted) return;
    try {
      await _service.voidAcquisition(assetId: summary.asset.id, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('financial_management.void_success'.tr())),
        );
      }
    } catch (error) {
      if (mounted) _showError(_message(error));
    }
  }

  Future<String?> _askVoidReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('financial_management.void_title'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'financial_management.void_reason'.tr(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: Text('financial_management.void_action'.tr()),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  static String _message(Object error) =>
      error.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
}

class _AssetCard extends StatelessWidget {
  final FixedAsset asset;
  final FixedAssetService service;
  final CurrencyService currency;
  final ValueChanged<FixedAssetSummary> onPostDepreciation;
  final ValueChanged<FixedAssetSummary> onVoidDepreciation;
  final ValueChanged<FixedAssetSummary> onVoidAsset;

  const _AssetCard({
    required this.asset,
    required this.service,
    required this.currency,
    required this.onPostDepreciation,
    required this.onVoidDepreciation,
    required this.onVoidAsset,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FixedAssetSummary>(
      future: service.getSummary(asset.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: LinearProgressIndicator(),
            ),
          );
        }
        final summary = snapshot.data!;
        final voided = asset.status == 'voided';
        final progress = asset.usefulLifeMonths == 0
            ? 0.0
            : (summary.postedInstallments / asset.usefulLifeMonths).clamp(
                0.0,
                1.0,
              );
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      child: Icon(
                        asset.category == 'furniture'
                            ? Icons.chair_outlined
                            : Icons.ac_unit_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            asset.name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${asset.assetNumber} • '
                            '${'financial_management.asset_category_${asset.category}'.tr()}',
                          ),
                        ],
                      ),
                    ),
                    if (!voided)
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'void_dep') {
                            onVoidDepreciation(summary);
                          } else if (value == 'void_asset') {
                            onVoidAsset(summary);
                          }
                        },
                        itemBuilder: (_) => [
                          if (summary.latestDepreciationId != null)
                            PopupMenuItem(
                              value: 'void_dep',
                              child: Text(
                                'financial_management.depreciation_void_latest'
                                    .tr(),
                              ),
                            ),
                          PopupMenuItem(
                            value: 'void_asset',
                            child: Text('financial_management.asset_void'.tr()),
                          ),
                        ],
                      ),
                  ],
                ),
                if (voided)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Chip(
                      label: Text('financial_management.status_voided'.tr()),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _AssetMetric(
                        label: 'financial_management.asset_cost'.tr(),
                        value: currency.formatCents(
                          asset.costCents.toBigInt().toInt(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _AssetMetric(
                        label: 'financial_management.asset_accumulated_dep'
                            .tr(),
                        value: currency.formatCents(
                          summary.accumulatedDepreciationCents,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _AssetMetric(
                        label: 'financial_management.asset_carrying'.tr(),
                        value: currency.formatCents(
                          summary.carryingAmountCents,
                        ),
                        emphasized: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 6),
                Text(
                  'financial_management.depreciation_progress'.tr(
                    args: [
                      summary.postedInstallments.toString(),
                      asset.usefulLifeMonths.toString(),
                    ],
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (!voided && !summary.fullyDepreciated)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          summary.depreciationDue
                              ? 'financial_management.depreciation_due'.tr()
                              : 'financial_management.depreciation_next'.tr(
                                  args: [
                                    DateFormat.yMMMd(
                                      context.locale.toString(),
                                    ).format(summary.nextDepreciationDate!),
                                  ],
                                ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: summary.depreciationDue
                            ? () => onPostDepreciation(summary)
                            : null,
                        icon: const Icon(Icons.calculate_outlined),
                        label: Text(
                          'financial_management.depreciation_post_next'.tr(),
                        ),
                      ),
                    ],
                  ),
                if (summary.fullyDepreciated)
                  Text(
                    'financial_management.asset_fully_depreciated'.tr(),
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AssetMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _AssetMetric({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 3),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: emphasized ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _FixedAssetDialog extends StatefulWidget {
  final FixedAssetService service;
  final List<Account> assetAccounts;
  final List<Account> fundingAccounts;
  final int currencyId;

  const _FixedAssetDialog({
    required this.service,
    required this.assetAccounts,
    required this.fundingAccounts,
    required this.currencyId,
  });

  @override
  State<_FixedAssetDialog> createState() => _FixedAssetDialogState();
}

class _FixedAssetDialogState extends State<_FixedAssetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _cost = TextEditingController();
  final _residual = TextEditingController(text: '0');
  final _lifeMonths = TextEditingController(text: '60');
  String _category = 'equipment';
  late Account _assetAccount;
  late Account _fundingAccount;
  DateTime _acquisitionDate = DateTime.now();
  DateTime _inServiceDate = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _assetAccount = widget.assetAccounts.firstWhere(
      (a) => a.accountCode == '1520',
      orElse: () => widget.assetAccounts.first,
    );
    _fundingAccount = widget.fundingAccounts.firstWhere(
      (a) => a.accountCode == '1010',
      orElse: () => widget.fundingAccounts.first,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _cost.dispose();
    _residual.dispose();
    _lifeMonths.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('financial_management.asset_add'.tr()),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: 'financial_management.asset_name'.tr(),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'financial_management.asset_name_required'.tr()
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: InputDecoration(
                    labelText: 'financial_management.asset_category'.tr(),
                  ),
                  items: const ['equipment', 'furniture']
                      .map(
                        (category) => DropdownMenuItem(
                          value: category,
                          child: Text(
                            'financial_management.asset_category_$category'
                                .tr(),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _changeCategory,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Account>(
                  initialValue: _fundingAccount,
                  decoration: InputDecoration(
                    labelText: 'financial_management.asset_funding'.tr(),
                  ),
                  items: widget.fundingAccounts
                      .map(
                        (account) => DropdownMenuItem(
                          value: account,
                          child: Text(
                            '${account.accountCode} — '
                            '${localizedAccountName(account)}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _fundingAccount = value!),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cost,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'financial_management.asset_cost'.tr(),
                        ),
                        validator: _validatePositiveMoney,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _residual,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'financial_management.asset_residual'.tr(),
                        ),
                        validator: _validateNonNegativeMoney,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lifeMonths,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'financial_management.asset_life_months'.tr(),
                  ),
                  validator: (value) => (int.tryParse(value ?? '') ?? 0) <= 0
                      ? 'financial_management.asset_life_required'.tr()
                      : null,
                ),
                const SizedBox(height: 8),
                _DateField(
                  label: 'financial_management.asset_acquisition_date'.tr(),
                  date: _acquisitionDate,
                  onTap: () => _pickDate(inService: false),
                ),
                _DateField(
                  label: 'financial_management.asset_in_service_date'.tr(),
                  date: _inServiceDate,
                  onTap: () => _pickDate(inService: true),
                ),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'financial_management.notes_optional'.tr(),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'financial_management.posting_preview'.tr(
                      args: [
                        _assetAccount.accountCode,
                        _fundingAccount.accountCode,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('common.save'.tr()),
        ),
      ],
    );
  }

  void _changeCategory(String? value) {
    if (value == null) return;
    final wantedCode = value == 'furniture' ? '1510' : '1520';
    setState(() {
      _category = value;
      _assetAccount = widget.assetAccounts.firstWhere(
        (account) => account.accountCode == wantedCode,
        orElse: () => widget.assetAccounts.first,
      );
    });
  }

  String? _validatePositiveMoney(String? value) {
    final result = sl<MoneyInputParser>().parse(value);
    return !result.isValid || result.cents <= 0
        ? 'financial_management.amount_required'.tr()
        : null;
  }

  String? _validateNonNegativeMoney(String? value) {
    final result = sl<MoneyInputParser>().parse(value);
    return !result.isValid ? 'financial_management.amount_invalid'.tr() : null;
  }

  Future<void> _pickDate({required bool inService}) async {
    final current = inService ? _inServiceDate : _acquisitionDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (inService) {
        _inServiceDate = picked;
      } else {
        _acquisitionDate = picked;
        if (_inServiceDate.isBefore(picked)) _inServiceDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final cost = sl<MoneyInputParser>().parse(_cost.text).cents;
    final residual = sl<MoneyInputParser>().parse(_residual.text).cents;
    if (residual >= cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('financial_management.asset_residual_invalid'.tr()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await widget.service.acquire(
        name: _name.text,
        category: _category,
        description: _description.text,
        acquisitionDate: _acquisitionDate,
        inServiceDate: _inServiceDate,
        costCents: cost,
        residualValueCents: residual,
        usefulLifeMonths: int.parse(_lifeMonths.text),
        assetAccountId: _assetAccount.id,
        fundingAccountId: _fundingAccount.id,
        currencyId: widget.currencyId,
      );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), ''),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(DateFormat.yMMMd(context.locale.toString()).format(date)),
      trailing: const Icon(Icons.calendar_today_outlined),
      onTap: onTap,
    );
  }
}

class _EmptyAssets extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyAssets({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.business_outlined,
              size: 64,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
