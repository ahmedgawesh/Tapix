import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/models/barcode_design_state.dart';
import '../bloc/barcode_design_bloc.dart';
import '../bloc/barcode_design_event.dart';

export '../bloc/barcode_design_event.dart' show LabelPrintMode, QuantityMode;

class DesignSettingsWidget extends StatelessWidget {
  final BarcodeDesignSettings settings;
  final bool isCompact;

  const DesignSettingsWidget({
    super.key,
    required this.settings,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return _CompactSettings(settings: settings);
    }
    return _FullSettings(settings: settings);
  }
}

class _CompactSettings extends StatelessWidget {
  final BarcodeDesignSettings settings;

  const _CompactSettings({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Copies row
          Row(
            children: [
              Text('barcode.copies'.tr()),
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.minus, size: 18),
                onPressed: settings.copies > 1
                    ? () => context
                        .read<BarcodeDesignBloc>()
                        .add(UpdateCopies(settings.copies - 1))
                    : null,
                visualDensity: VisualDensity.compact,
              ),
              Text(
                '${settings.copies}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(LucideIcons.plus, size: 18),
                onPressed: () => context
                    .read<BarcodeDesignBloc>()
                    .add(UpdateCopies(settings.copies + 1)),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const Divider(),
          // Quick toggles
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _QuickToggle(
                label: 'barcode.name'.tr(),
                value: settings.includeName,
                onChanged: (v) => context
                    .read<BarcodeDesignBloc>()
                    .add(ToggleIncludeName(v)),
              ),
              _QuickToggle(
                label: 'barcode.price'.tr(),
                value: settings.includePrice,
                onChanged: (v) => context
                    .read<BarcodeDesignBloc>()
                    .add(ToggleIncludePrice(v)),
              ),
              _QuickToggle(
                label: 'barcode.sku'.tr(),
                value: settings.includeSku,
                onChanged: (v) => context
                    .read<BarcodeDesignBloc>()
                    .add(ToggleIncludeSku(v)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _QuickToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
      selectedColor: colorScheme.primaryContainer,
      checkmarkColor: colorScheme.primary,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _FullSettings extends StatelessWidget {
  final BarcodeDesignSettings settings;

  const _FullSettings({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label dimensions
        _SectionHeader(title: 'barcode.label_size'.tr()),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _DimensionField(
                label: 'barcode.width_mm'.tr(),
                value: settings.labelWidthMm,
                onChanged: (v) => context
                    .read<BarcodeDesignBloc>()
                    .add(UpdateLabelDimensions(widthMm: v)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _DimensionField(
                label: 'barcode.height_mm'.tr(),
                value: settings.labelHeightMm,
                onChanged: (v) => context
                    .read<BarcodeDesignBloc>()
                    .add(UpdateLabelDimensions(heightMm: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Barcode type
        _SectionHeader(title: 'barcode.type'.tr()),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            prefixIcon: Icon(LucideIcons.scan),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: settings.barcodeType,
              isExpanded: true,
              isDense: true,
              items: [
                DropdownMenuItem(value: 'auto', child: Text('barcode.type_auto'.tr())),
                DropdownMenuItem(value: 'code128', child: Text('barcode.type_code128'.tr())),
                DropdownMenuItem(value: 'ean13', child: Text('barcode.type_ean13'.tr())),
                DropdownMenuItem(value: 'ean8', child: Text('barcode.type_ean8'.tr())),
                DropdownMenuItem(value: 'upca', child: Text('barcode.type_upca'.tr())),
                DropdownMenuItem(value: 'qr', child: Text('barcode.type_qr'.tr())),
              ],
              onChanged: (v) {
                if (v != null) {
                  context.read<BarcodeDesignBloc>().add(UpdateBarcodeType(v));
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Copies
        _SectionHeader(title: 'barcode.copies'.tr()),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton.filled(
              icon: const Icon(LucideIcons.minus),
              onPressed: settings.copies > 1
                  ? () => context
                      .read<BarcodeDesignBloc>()
                      .add(UpdateCopies(settings.copies - 1))
                  : null,
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${settings.copies}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            ),
            IconButton.filled(
              icon: const Icon(LucideIcons.plus),
              onPressed: () => context
                  .read<BarcodeDesignBloc>()
                  .add(UpdateCopies(settings.copies + 1)),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Print mode (Thermal vs A4)
        _SectionHeader(title: 'barcode.print_mode'.tr()),
        const SizedBox(height: 8),
        SegmentedButton<LabelPrintMode>(
          segments: [
            ButtonSegment(
              value: LabelPrintMode.thermal,
              label: Text('barcode.thermal'.tr()),
              icon: const Icon(LucideIcons.receipt),
            ),
            ButtonSegment(
              value: LabelPrintMode.a4Sheet,
              label: Text('barcode.a4_sheet'.tr()),
              icon: const Icon(LucideIcons.layoutGrid),
            ),
          ],
          selected: {settings.printMode},
          onSelectionChanged: (selected) {
            context.read<BarcodeDesignBloc>().add(UpdatePrintMode(selected.first));
          },
        ),
        const SizedBox(height: 16),
        
        // A4 specific settings
        if (settings.isA4Mode) ..._buildA4Settings(context, settings),
        
        // Quantity mode
        _SectionHeader(title: 'barcode.quantity_mode'.tr()),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text('barcode.qty_single'.tr()),
              selected: settings.quantityMode == QuantityMode.single,
              onSelected: (v) => v ? context.read<BarcodeDesignBloc>().add(const UpdateQuantityMode(QuantityMode.single)) : null,
            ),
            ChoiceChip(
              label: Text('barcode.qty_custom'.tr()),
              selected: settings.quantityMode == QuantityMode.custom,
              onSelected: (v) => v ? context.read<BarcodeDesignBloc>().add(const UpdateQuantityMode(QuantityMode.custom)) : null,
            ),
            ChoiceChip(
              label: Text('barcode.qty_invoice'.tr()),
              selected: settings.quantityMode == QuantityMode.invoiceQuantity,
              onSelected: (v) => v ? context.read<BarcodeDesignBloc>().add(const UpdateQuantityMode(QuantityMode.invoiceQuantity)) : null,
            ),
            ChoiceChip(
              label: Text('barcode.qty_stock'.tr()),
              selected: settings.quantityMode == QuantityMode.stockQuantity,
              onSelected: (v) => v ? context.read<BarcodeDesignBloc>().add(const UpdateQuantityMode(QuantityMode.stockQuantity)) : null,
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Label content toggles
        _SectionHeader(title: 'barcode.label_content'.tr()),
        const SizedBox(height: 8),
        SwitchListTile(
          title: Text('barcode.include_name'.tr()),
          value: settings.includeName,
          onChanged: (v) => context
              .read<BarcodeDesignBloc>()
              .add(ToggleIncludeName(v)),
          dense: true,
        ),
        SwitchListTile(
          title: Text('barcode.include_price'.tr()),
          value: settings.includePrice,
          onChanged: (v) => context
              .read<BarcodeDesignBloc>()
              .add(ToggleIncludePrice(v)),
          dense: true,
        ),
        SwitchListTile(
          title: Text('barcode.include_barcode'.tr()),
          value: settings.includeBarcode,
          onChanged: (v) => context
              .read<BarcodeDesignBloc>()
              .add(ToggleIncludeBarcode(v)),
          dense: true,
        ),
        SwitchListTile(
          title: Text('barcode.include_sku'.tr()),
          value: settings.includeSku,
          onChanged: (v) => context
              .read<BarcodeDesignBloc>()
              .add(ToggleIncludeSku(v)),
          dense: true,
        ),
        SwitchListTile(
          title: Text('barcode.include_company'.tr()),
          value: settings.includeCompanyName,
          onChanged: (v) => context
              .read<BarcodeDesignBloc>()
              .add(ToggleIncludeCompanyName(v)),
          dense: true,
        ),
        SwitchListTile(
          title: Text('barcode.include_company_contact'.tr()),
          value: settings.includeCompanyContact,
          onChanged: (v) => context
              .read<BarcodeDesignBloc>()
              .add(ToggleIncludeCompanyContact(v)),
          dense: true,
        ),
        SwitchListTile(
          title: Text('barcode.include_variant'.tr()),
          subtitle: Text('barcode.variant_hint'.tr()),
          value: settings.includeVariantInfo,
          onChanged: (v) => context
              .read<BarcodeDesignBloc>()
              .add(ToggleIncludeVariantInfo(v)),
          dense: true,
        ),
      ],
    );
  }
  
  List<Widget> _buildA4Settings(BuildContext context, BarcodeDesignSettings settings) {
    return [
      // Labels per row
      Row(
        children: [
          Expanded(
            child: Text('barcode.labels_per_row'.tr()),
          ),
          IconButton(
            icon: const Icon(LucideIcons.minus, size: 18),
            onPressed: settings.labelsPerRow > 1
                ? () => context.read<BarcodeDesignBloc>().add(UpdateLabelsPerRow(settings.labelsPerRow - 1))
                : null,
            visualDensity: VisualDensity.compact,
          ),
          Text(
            '${settings.labelsPerRow}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(LucideIcons.plus, size: 18),
            onPressed: settings.labelsPerRow < 10
                ? () => context.read<BarcodeDesignBloc>().add(UpdateLabelsPerRow(settings.labelsPerRow + 1))
                : null,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      const SizedBox(height: 8),
      
      // Gap settings
      Row(
        children: [
          Expanded(
            child: _DimensionField(
              label: 'barcode.h_gap'.tr(),
              value: settings.horizontalGapMm,
              onChanged: (v) => context.read<BarcodeDesignBloc>().add(UpdateA4LayoutGaps(horizontalGapMm: v)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _DimensionField(
              label: 'barcode.v_gap'.tr(),
              value: settings.verticalGapMm,
              onChanged: (v) => context.read<BarcodeDesignBloc>().add(UpdateA4LayoutGaps(verticalGapMm: v)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      
      // Page margin
      _DimensionField(
        label: 'barcode.page_margin'.tr(),
        value: settings.pageMarginMm,
        onChanged: (v) => context.read<BarcodeDesignBloc>().add(UpdateA4LayoutGaps(pageMarginMm: v)),
      ),
      const SizedBox(height: 8),
      
      // Info about calculated layout
      Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              const Icon(LucideIcons.info, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'barcode.a4_layout_info'.tr(args: [
                    settings.labelsPerRow.toString(),
                    settings.calculatedLabelsPerColumn.toString(),
                    settings.labelsPerPage.toString(),
                  ]),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
    ];
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

class _DimensionField extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _DimensionField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_DimensionField> createState() => _DimensionFieldState();
}

class _DimensionFieldState extends State<_DimensionField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toStringAsFixed(1));
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(_DimensionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      // Only update text if not currently focused to avoid cursor jumping
      if (!_controller.selection.isValid || !_controller.selection.isCollapsed) {
        final newText = widget.value.toStringAsFixed(1);
        if (_controller.text != newText) {
          _controller.text = newText;
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        suffixText: 'mm',
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (v) {
        final parsed = double.tryParse(v);
        if (parsed != null && parsed > 0) {
          widget.onChanged(parsed);
        }
      },
      onTap: () {
        // Select all text on tap for easy editing
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      },
    );
  }
}
