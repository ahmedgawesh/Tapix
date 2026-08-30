import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/database/app_database.dart' show ActiveIngredient;
import '../../../../core/database/daos/pharmacy_dao.dart';
import '../../../../core/di/injection_container.dart';
import '../bloc/product_form_bloc.dart';

const medicineDosageForms = <String>[
  'tablet',
  'capsule',
  'syrup',
  'suspension',
  'solution',
  'cream',
  'ointment',
  'gel',
  'drops',
  'injection',
  'vial',
  'ampoule',
  'inhaler',
  'suppository',
  'powder',
  'spray',
];

const medicineAdministrationRoutes = <String>[
  'oral',
  'topical',
  'ophthalmic',
  'otic',
  'nasal',
  'inhalation',
  'rectal',
  'vaginal',
  'intramuscular',
  'intravenous',
  'subcutaneous',
];

const medicineStrengthUnits = <String>[
  'mg',
  'g',
  'mcg',
  'IU',
  'unit',
  'mmol',
  'mEq',
  '%',
];

const medicineBasisUnits = <String>[
  'ml',
  'l',
  'dose',
  'tablet',
  'capsule',
  'actuation',
];

class MedicineProfileFormSection extends StatelessWidget {
  const MedicineProfileFormSection({
    super.key,
    required this.state,
    this.onShowAlternatives,
  });

  final ProductFormState state;
  final VoidCallback? onShowAlternatives;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<ProductFormBloc>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.pill,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'pharmacy.form.title'.tr(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (state.isEditing && state.isMedicine)
                  IconButton(
                    tooltip: 'pharmacy.alternatives.button'.tr(),
                    onPressed: onShowAlternatives,
                    icon: const Icon(LucideIcons.listPlus),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('pharmacy.form.is_medicine'.tr()),
              subtitle: Text('pharmacy.form.is_medicine_desc'.tr()),
              value: state.isMedicine,
              onChanged: (value) => bloc.add(
                ProductFormFieldChanged(field: 'isMedicine', value: value),
              ),
            ),
            if (state.isMedicine) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: state.medicineDosageForm,
                      decoration: InputDecoration(
                        labelText: 'pharmacy.form.dosage_form'.tr(),
                        errorText: state.fieldErrors['medicineDosageForm']
                            ?.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      items: medicineDosageForms
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text('pharmacy.forms.$value'.tr()),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        bloc.add(
                          ProductFormFieldChanged(
                            field: 'medicineDosageForm',
                            value: value,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: state.medicineRoute,
                      decoration: InputDecoration(
                        labelText: 'pharmacy.form.route'.tr(),
                        errorText: state.fieldErrors['medicineRoute']?.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      items: medicineAdministrationRoutes
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text('pharmacy.routes.$value'.tr()),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        bloc.add(
                          ProductFormFieldChanged(
                            field: 'medicineRoute',
                            value: value,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (
                var index = 0;
                index < state.medicineIngredients.length;
                index++
              )
                _IngredientCard(
                  key: ValueKey(
                    'medicine-${state.medicineIngredients[index].ingredientId}',
                  ),
                  ingredient: state.medicineIngredients[index],
                  errorText: state.fieldErrors['medicineStrength']?.tr(),
                  onChanged: (updated) => _replaceIngredient(
                    bloc,
                    state.medicineIngredients,
                    index,
                    updated,
                  ),
                  onRemove: () =>
                      _removeIngredient(bloc, state.medicineIngredients, index),
                ),
              if (state.fieldErrors['medicineIngredients'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    state.fieldErrors['medicineIngredients']!.tr(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _addIngredient(context, state),
                  icon: const Icon(LucideIcons.plus),
                  label: Text('pharmacy.form.add_ingredient'.tr()),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('pharmacy.form.eligible'.tr()),
                subtitle: Text('pharmacy.form.eligible_desc'.tr()),
                value: state.medicineSubstitutionEligible,
                onChanged: (value) => bloc.add(
                  ProductFormFieldChanged(
                    field: 'medicineSubstitutionEligible',
                    value: value,
                  ),
                ),
              ),
              TextFormField(
                key: ValueKey('medicine-notes-${state.productId}'),
                initialValue: state.medicineNotes,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'pharmacy.form.notes'.tr(),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => bloc.add(
                  ProductFormFieldChanged(field: 'medicineNotes', value: value),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addIngredient(
    BuildContext context,
    ProductFormState state,
  ) async {
    final selected = await showModalBottomSheet<ActiveIngredient>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _IngredientPickerSheet(),
    );
    if (selected == null || !context.mounted) return;
    if (state.medicineIngredients.any(
      (row) => row.ingredientId == selected.id,
    )) {
      return;
    }
    final locale = context.locale.languageCode;
    final displayName = locale == 'ar'
        ? selected.nameAr
        : locale == 'fr'
        ? selected.nameFr
        : selected.canonicalName;
    context.read<ProductFormBloc>().add(
      ProductFormFieldChanged(
        field: 'medicineIngredients',
        value: [
          ...state.medicineIngredients,
          MedicineIngredientDraft(
            ingredientId: selected.id,
            displayName: displayName?.trim().isNotEmpty == true
                ? displayName
                : selected.canonicalName,
            value: '',
            unit: 'mg',
          ),
        ],
      ),
    );
  }

  void _replaceIngredient(
    ProductFormBloc bloc,
    List<MedicineIngredientDraft> ingredients,
    int index,
    MedicineIngredientDraft updated,
  ) {
    final next = [...ingredients]..[index] = updated;
    bloc.add(
      ProductFormFieldChanged(field: 'medicineIngredients', value: next),
    );
  }

  void _removeIngredient(
    ProductFormBloc bloc,
    List<MedicineIngredientDraft> ingredients,
    int index,
  ) {
    final next = [...ingredients]..removeAt(index);
    bloc.add(
      ProductFormFieldChanged(field: 'medicineIngredients', value: next),
    );
  }
}

class _IngredientCard extends StatelessWidget {
  const _IngredientCard({
    super.key,
    required this.ingredient,
    required this.onChanged,
    required this.onRemove,
    this.errorText,
  });

  final MedicineIngredientDraft ingredient;
  final ValueChanged<MedicineIngredientDraft> onChanged;
  final VoidCallback onRemove;
  final String? errorText;

  MedicineIngredientDraft _copy({
    String? value,
    String? unit,
    Object? basisValue = _notSet,
    Object? basisUnit = _notSet,
  }) {
    return MedicineIngredientDraft(
      ingredientId: ingredient.ingredientId,
      displayName: ingredient.displayName,
      value: value ?? ingredient.value,
      unit: unit ?? ingredient.unit,
      basisValue: identical(basisValue, _notSet)
          ? ingredient.basisValue
          : basisValue as String?,
      basisUnit: identical(basisUnit, _notSet)
          ? ingredient.basisUnit
          : basisUnit as String?,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasBasis = ingredient.basisValue != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ingredient.displayName ??
                        '${'pharmacy.form.ingredient'.tr()} #${ingredient.ingredientId}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'pharmacy.form.remove'.tr(),
                  onPressed: onRemove,
                  icon: const Icon(LucideIcons.trash2),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('strength-${ingredient.ingredientId}'),
                    initialValue: ingredient.value,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'pharmacy.form.strength'.tr(),
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => onChanged(_copy(value: value)),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 105,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue:
                        medicineStrengthUnits.contains(ingredient.unit)
                        ? ingredient.unit
                        : 'mg',
                    decoration: InputDecoration(
                      labelText: 'pharmacy.form.unit'.tr(),
                      border: const OutlineInputBorder(),
                    ),
                    items: medicineStrengthUnits
                        .map(
                          (unit) =>
                              DropdownMenuItem(value: unit, child: Text(unit)),
                        )
                        .toList(),
                    onChanged: (unit) {
                      if (unit != null) onChanged(_copy(unit: unit));
                    },
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('pharmacy.form.per'.tr()),
              value: hasBasis,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (enabled) => onChanged(
                enabled == true
                    ? _copy(basisValue: '1', basisUnit: 'ml')
                    : _copy(basisValue: null, basisUnit: null),
              ),
            ),
            if (hasBasis)
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('basis-${ingredient.ingredientId}'),
                      initialValue: ingredient.basisValue,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'pharmacy.form.per'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) => onChanged(_copy(basisValue: value)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 125,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue:
                          medicineBasisUnits.contains(ingredient.basisUnit)
                          ? ingredient.basisUnit
                          : 'ml',
                      decoration: InputDecoration(
                        labelText: 'pharmacy.form.basis_unit'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      items: medicineBasisUnits
                          .map(
                            (unit) => DropdownMenuItem(
                              value: unit,
                              child: Text(unit),
                            ),
                          )
                          .toList(),
                      onChanged: (unit) {
                        if (unit != null) {
                          onChanged(_copy(basisUnit: unit));
                        }
                      },
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _IngredientPickerSheet extends StatefulWidget {
  const _IngredientPickerSheet();

  @override
  State<_IngredientPickerSheet> createState() => _IngredientPickerSheetState();
}

class _IngredientPickerSheetState extends State<_IngredientPickerSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<ActiveIngredient> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await sl<PharmacyDao>().searchActiveIngredients(
      _searchController.text,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  void _search(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
  }

  String _name(BuildContext context, ActiveIngredient ingredient) {
    final locale = context.locale.languageCode;
    final localized = locale == 'ar'
        ? ingredient.nameAr
        : locale == 'fr'
        ? ingredient.nameFr
        : null;
    return localized?.trim().isNotEmpty == true
        ? localized!
        : ingredient.canonicalName;
  }

  Future<void> _create() async {
    final ingredient = await showDialog<ActiveIngredient>(
      context: context,
      builder: (_) =>
          _CreateIngredientDialog(initialName: _searchController.text),
    );
    if (ingredient != null && mounted) {
      Navigator.of(context).pop(ingredient);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'pharmacy.form.search_ingredient'.tr(),
                  prefixIcon: const Icon(LucideIcons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: _search,
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _create,
                  icon: const Icon(LucideIcons.plus),
                  label: Text('pharmacy.form.new_ingredient'.tr()),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final ingredient = _items[index];
                          return ListTile(
                            leading: const Icon(LucideIcons.pill),
                            title: Text(_name(context, ingredient)),
                            subtitle: Text(ingredient.canonicalName),
                            onTap: () => Navigator.pop(context, ingredient),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateIngredientDialog extends StatefulWidget {
  const _CreateIngredientDialog({required this.initialName});

  final String initialName;

  @override
  State<_CreateIngredientDialog> createState() =>
      _CreateIngredientDialogState();
}

class _CreateIngredientDialogState extends State<_CreateIngredientDialog> {
  late final TextEditingController _canonicalController;
  final _arabicController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _canonicalController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _canonicalController.dispose();
    _arabicController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _canonicalController.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final saved = await sl<PharmacyDao>().saveActiveIngredient(
        canonicalName: _canonicalController.text,
        nameAr: _arabicController.text,
      );
      if (mounted) Navigator.of(context).pop(saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('pharmacy.validation.save_failed'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text('pharmacy.form.new_ingredient'.tr()),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _canonicalController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'pharmacy.form.ingredient_name'.tr(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _arabicController,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: 'pharmacy.form.ingredient_name_ar'.tr(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
}

const Object _notSet = Object();
