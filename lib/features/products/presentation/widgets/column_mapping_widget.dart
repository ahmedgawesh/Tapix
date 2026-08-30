import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../domain/entities/import_file_data.dart';
import '../bloc/import_products_bloc.dart';
import '../bloc/import_products_event.dart';
import '../bloc/import_products_state.dart';

class ColumnMappingWidget extends StatefulWidget {
  final ImportProductsState state;
  final bool isDesktop;
  final bool isTablet;

  const ColumnMappingWidget({
    super.key,
    required this.state,
    required this.isDesktop,
    required this.isTablet,
  });

  @override
  State<ColumnMappingWidget> createState() => _ColumnMappingWidgetState();
}

class _ColumnMappingWidgetState extends State<ColumnMappingWidget> {
  final Map<String, int?> _fieldToColumnIndex = {};
  bool _hasInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitialized && widget.state is ImportFileParsed) {
      _initializeAutoMapping();
      _hasInitialized = true;
    }
  }

  void _initializeAutoMapping() {
    final state = widget.state as ImportFileParsed;
    // Normalize headers: lowercase and replace spaces with underscores
    // so that 'Stock Quantity' matches field 'stock_quantity'
    final headers = state.fileData.headers
        .map((h) => h.toLowerCase().replaceAll(' ', '_'))
        .toList();

    for (final field in state.availableFields) {
      final fieldName = field.fieldName.toLowerCase();
      // Prefer exact match first, then fallback to contains
      var index = headers.indexWhere((h) => h == fieldName);
      if (index == -1) {
        index = headers.indexWhere((h) => h.contains(fieldName));
      }
      if (index != -1) {
        _fieldToColumnIndex[field.fieldName] = index;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = widget.state;

    if (state is! ImportFileParsed && state is! ImportColumnMappingReady) {
      return const SizedBox.shrink();
    }

    final fileData = state is ImportFileParsed
        ? state.fileData
        : (state as ImportColumnMappingReady).fileData;
    final availableFields = state is ImportFileParsed
        ? state.availableFields
        : (state as ImportColumnMappingReady).availableFields;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.fileText, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileData.fileName,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'import_products.rows_found'.tr(
                              args: [fileData.totalRows.toString()],
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'import_products.map_columns'.tr(),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'import_products.map_columns_hint'.tr(),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        ...availableFields.map(
          (field) =>
              _buildFieldMapping(context, field, fileData.headers, colorScheme),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: () {
                context.read<ImportProductsBloc>().add(const ImportReset());
              },
              child: Text('import_products.cancel'.tr()),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: _canProceed() ? _proceedToValidation : null,
              icon: const Icon(LucideIcons.arrowRight),
              label: Text('import_products.validate'.tr()),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFieldMapping(
    BuildContext context,
    ImportFieldDefinition field,
    List<String> headers,
    ColorScheme colorScheme,
  ) {
    final selectedIndex = _fieldToColumnIndex[field.fieldName];

    final isNarrow = MediaQuery.of(context).size.width < 520;

    final labelWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                field.displayName,
                style: Theme.of(context).textTheme.bodyLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (field.isRequired) ...[
              const SizedBox(width: 4),
              Text('*', style: TextStyle(color: colorScheme.error)),
            ],
          ],
        ),
        if (field.hint != null)
          Text(
            field.hint!,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
      ],
    );

    final dropdownWidget = DropdownButtonFormField<int?>(
      initialValue: selectedIndex,
      isExpanded: true,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        errorText: field.isRequired && selectedIndex == null
            ? 'import_products.required_field'.tr()
            : null,
      ),
      hint: Text(
        'import_products.select_column'.tr(),
        overflow: TextOverflow.ellipsis,
      ),
      items: [
        DropdownMenuItem<int?>(
          value: null,
          child: Text(
            'import_products.skip_field'.tr(),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ...headers.asMap().entries.map((entry) {
          return DropdownMenuItem<int?>(
            value: entry.key,
            child: Text(
              '${entry.value} ${'import_products.column_reference'.tr()} ${entry.key + 1})',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          );
        }),
      ],
      onChanged: (value) {
        setState(() {
          _fieldToColumnIndex[field.fieldName] = value;
        });
      },
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: isNarrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                labelWidget,
                const SizedBox(height: 8),
                dropdownWidget,
              ],
            )
          : Row(
              children: [
                Expanded(flex: 2, child: labelWidget),
                const SizedBox(width: 16),
                Expanded(flex: 3, child: dropdownWidget),
              ],
            ),
    );
  }

  bool _canProceed() {
    final state = widget.state;
    final availableFields = state is ImportFileParsed
        ? state.availableFields
        : (state as ImportColumnMappingReady).availableFields;

    for (final field in availableFields) {
      if (field.isRequired && _fieldToColumnIndex[field.fieldName] == null) {
        return false;
      }
    }
    return true;
  }

  void _proceedToValidation() {
    final mappedFields = Map<String, int>.fromEntries(
      _fieldToColumnIndex.entries
          .where((entry) => entry.value != null)
          .map((entry) => MapEntry(entry.key, entry.value!)),
    );
    final columnMapping = ColumnMapping(mappedFields);
    context.read<ImportProductsBloc>().add(ImportColumnMapped(columnMapping));
    context.read<ImportProductsBloc>().add(const ImportValidationRequested());
  }
}
