import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/currency_bloc.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/bloc/realtime_bloc.dart';

class CurrencyPickerDialog extends StatefulWidget {
  const CurrencyPickerDialog({super.key});

  @override
  State<CurrencyPickerDialog> createState() => _CurrencyPickerDialogState();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => BlocProvider.value(
        value: context.read<CurrencyBloc>(),
        child: const CurrencyPickerDialog(),
      ),
    );
  }
}

class _CurrencyPickerDialogState extends State<CurrencyPickerDialog> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Currency> _filteredCurrencies(String currentCode) {
    final all = Currency.allCurrencies;
    if (_searchQuery.isEmpty) return all;

    final q = _searchQuery.toLowerCase();
    return all.where((c) {
      final translatedName = 'currency.${c.code}'.tr();
      return c.code.toLowerCase().contains(q) ||
          c.name.toLowerCase().contains(q) ||
          c.symbol.toLowerCase().contains(q) ||
          translatedName.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(LucideIcons.dollarSign, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'currency_picker.title'.tr(),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(LucideIcons.plus),
                    tooltip: 'currency_picker.add_custom'.tr(),
                    onPressed: () => _showAddCustomCurrencyDialog(context),
                  ),
                ],
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'currency_picker.search_hint'.tr(),
                  prefixIcon: const Icon(LucideIcons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(LucideIcons.x),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
            const SizedBox(height: 4),
            // Currency list
            Expanded(
              child: BlocBuilder<CurrencyBloc, RealtimeState<Currency>>(
                builder: (context, state) {
                  final currentCurrency = state is RealtimeSuccess<Currency>
                      ? state.data
                      : Currency.supportedCurrencies.first;

                  final currencies = _filteredCurrencies(currentCurrency.code);

                  if (currencies.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.searchX,
                            size: 48,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'currency_picker.no_results'.tr(),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed: () =>
                                _showAddCustomCurrencyDialog(context),
                            icon: const Icon(LucideIcons.plus),
                            label: Text('currency_picker.add_custom'.tr()),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    itemCount: currencies.length,
                    itemBuilder: (context, index) {
                      final currency = currencies[index];
                      final isSelected = currency.code == currentCurrency.code;
                      final translatedName = 'currency.${currency.code}'.tr();
                      // If no translation found, use the English name
                      final displayName =
                          translatedName == 'currency.${currency.code}'
                          ? currency.name
                          : translatedName;

                      return ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colorScheme.primaryContainer
                                : colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            currency.symbol,
                            style: TextStyle(
                              color: isSelected
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        title: Text(
                          displayName,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected ? colorScheme.primary : null,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            Text(currency.code),
                            if (currency.isCustom) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'currency_picker.custom_label'.tr(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onTertiaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: isSelected
                            ? Icon(
                                LucideIcons.check,
                                color: colorScheme.primary,
                              )
                            : null,
                        selected: isSelected,
                        onTap: () {
                          context.read<CurrencyBloc>().add(
                            CurrencyChanged(currency.code),
                          );
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddCustomCurrencyDialog(BuildContext parentContext) async {
    final result = await showDialog<Currency>(
      context: context,
      builder: (context) => const _AddCustomCurrencyDialog(),
    );

    if (result != null && parentContext.mounted) {
      parentContext.read<CurrencyBloc>().add(
        CustomCurrencyAdded(result, setAsActive: true),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

class _AddCustomCurrencyDialog extends StatefulWidget {
  const _AddCustomCurrencyDialog();

  @override
  State<_AddCustomCurrencyDialog> createState() =>
      _AddCustomCurrencyDialogState();
}

class _AddCustomCurrencyDialogState extends State<_AddCustomCurrencyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _symbolController = TextEditingController();
  final _nameController = TextEditingController();
  int _decimalDigits = 2;
  SymbolPosition _symbolPosition = SymbolPosition.before;

  @override
  void dispose() {
    _codeController.dispose();
    _symbolController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text('currency_picker.add_custom_title'.tr()),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                maxLength: 5,
                decoration: InputDecoration(
                  labelText: 'currency_picker.code_label'.tr(),
                  hintText: 'currency_picker.code_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'currency_picker.code_required'.tr();
                  }
                  if (value.trim().length < 2) {
                    return 'currency_picker.code_too_short'.tr();
                  }
                  final existing = Currency.allCurrencies
                      .where((c) => c.code == value.trim().toUpperCase())
                      .toList();
                  if (existing.isNotEmpty) {
                    return 'currency_picker.code_exists'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _symbolController,
                maxLength: 5,
                decoration: InputDecoration(
                  labelText: 'currency_picker.symbol_label'.tr(),
                  hintText: 'currency_picker.symbol_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'currency_picker.symbol_required'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'currency_picker.name_label'.tr(),
                  hintText: 'currency_picker.name_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'currency_picker.name_required'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _decimalDigits,
                decoration: InputDecoration(
                  labelText: 'currency_picker.decimals_label'.tr(),
                  border: const OutlineInputBorder(),
                ),
                items: [0, 1, 2, 3].map((d) {
                  return DropdownMenuItem(value: d, child: Text('$d'));
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _decimalDigits = value);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<SymbolPosition>(
                initialValue: _symbolPosition,
                decoration: InputDecoration(
                  labelText: 'currency_picker.symbol_position_label'.tr(),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: SymbolPosition.before,
                    child: Text('currency_picker.symbol_before'.tr()),
                  ),
                  DropdownMenuItem(
                    value: SymbolPosition.after,
                    child: Text('currency_picker.symbol_after'.tr()),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _symbolPosition = value);
                },
              ),
              const SizedBox(height: 12),
              // Preview
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'currency_picker.preview'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _buildPreview(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _onSubmit,
          child: Text('currency_picker.add_button'.tr()),
        ),
      ],
    );
  }

  String _buildPreview() {
    final symbol = _symbolController.text.isEmpty
        ? '?'
        : _symbolController.text;
    final amount = _decimalDigits == 0
        ? '1,234'
        : '1,234.${'0' * _decimalDigits}';
    if (_symbolPosition == SymbolPosition.after) {
      return '$amount $symbol';
    }
    return '$symbol$amount';
  }

  void _onSubmit() {
    if (!_formKey.currentState!.validate()) return;

    final currency = Currency(
      code: _codeController.text.trim().toUpperCase(),
      symbol: _symbolController.text.trim(),
      name: _nameController.text.trim(),
      decimalDigits: _decimalDigits,
      symbolPosition: _symbolPosition,
      isCustom: true,
    );

    Navigator.of(context).pop(currency);
  }
}
