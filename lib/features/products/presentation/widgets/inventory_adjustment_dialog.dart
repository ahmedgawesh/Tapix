import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/inventory/inventory_adjustment_service.dart';
import '../../../../core/widgets/inputs/select_all_on_focus.dart';
import '../../domain/repositories/product_repository.dart';

/// Accounting-safe manual inventory adjustment dialog.
///
/// Single UI entry point for every manual stock or cost mutation that is NOT
/// driven by a purchase, sale, or return document. The dialog never touches
/// `product_variants.stock_quantity` directly — it delegates to
/// [InventoryAdjustmentService.adjustForProduct], which:
///
///   * requires a non-empty reason (mandatory audit trail),
///   * runs stock + GL + `inventory_adjustments` row writes inside ONE
///     transaction,
///   * posts a balanced journal entry (Dr/Cr) matching the chosen type:
///       - Shrinkage:   Dr 5800 / Cr 1200
///       - Gain:        Dr 1200 / Cr 4200
///       - Revaluation: Dr/Cr 1200 ↔ 5900 (sign by direction)
///
/// Mirrors the manual-adjustment UX used by QuickBooks Online, Xero, and
/// Odoo: type → quantity/cost → reason → preview → post.
class InventoryAdjustmentDialog extends StatefulWidget {
  final int productId;
  final int? variantId;
  final int currentStock;
  final String measurementType;

  /// Current unit cost in MINOR units (cents) — used to seed the revaluation
  /// new-cost field and to compute the book-value preview.
  final int currentUnitCostCents;

  /// Optional label shown at the top (e.g. "Blue / Medium" for a variant,
  /// or just the product name when adjusting the default variant).
  final String? subjectLabel;

  const InventoryAdjustmentDialog({
    super.key,
    required this.productId,
    this.variantId,
    required this.currentStock,
    this.measurementType = 'piece',
    required this.currentUnitCostCents,
    this.subjectLabel,
  });

  /// Shows the dialog. Returns `true` if an adjustment was posted
  /// successfully so the caller can refresh its data if needed.
  static Future<bool?> show(
    BuildContext context, {
    required int productId,
    int? variantId,
    required int currentStock,
    required int currentUnitCostCents,
    String? subjectLabel,
  }) async {
    final product = await sl<ProductRepository>().getProductById(productId);
    if (!context.mounted) return null;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InventoryAdjustmentDialog(
        productId: productId,
        variantId: variantId,
        currentStock: currentStock,
        measurementType: product?.measurementType ?? 'piece',
        currentUnitCostCents: currentUnitCostCents,
        subjectLabel: subjectLabel,
      ),
    );
  }

  @override
  State<InventoryAdjustmentDialog> createState() =>
      _InventoryAdjustmentDialogState();
}

class _InventoryAdjustmentDialogState extends State<InventoryAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qtyCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  InventoryAdjustmentType _type = InventoryAdjustmentType.shrinkage;
  late MeasurementUnit _quantityUnit;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _quantityUnit = MeasurementType.fromDb(widget.measurementType).majorUnit;
    _qtyCtrl.text = '1';
    _costCtrl.text = _fmtCents(widget.currentUnitCostCents);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _reasonCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  static String _fmtCents(int cents) {
    final d = (Decimal.fromInt(cents) / Decimal.fromInt(100)).toDecimal(
      scaleOnInfinitePrecision: 2,
    );
    return d.toString();
  }

  static int? _parseToCents(String raw) {
    final s = raw.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    final d = Decimal.tryParse(s);
    if (d == null) return null;
    return (d * Decimal.fromInt(100)).toBigInt().toInt();
  }

  // ── Preview helpers ────────────────────────────────────────
  int _qty() {
    try {
      return MeasuredQuantity.parseToStored(_qtyCtrl.text, _quantityUnit);
    } on FormatException {
      return 0;
    }
  }

  int? _newCostCents() => _parseToCents(_costCtrl.text);

  int _signedDelta() => switch (_type) {
    InventoryAdjustmentType.shrinkage => -_qty().abs(),
    InventoryAdjustmentType.gain => _qty().abs(),
    InventoryAdjustmentType.revaluation => 0,
    InventoryAdjustmentType.openingBalance => 0,
  };

  int _newStockPreview() => widget.currentStock + _signedDelta();

  int? _previewValueCents() {
    switch (_type) {
      case InventoryAdjustmentType.shrinkage:
      case InventoryAdjustmentType.gain:
        return MeasuredAmount.cents(
          unitCents: widget.currentUnitCostCents,
          quantity: _qty().abs(),
          quantityScale: MeasurementType.fromDb(
            widget.measurementType,
          ).quantityScale,
        );
      case InventoryAdjustmentType.revaluation:
        final nc = _newCostCents();
        if (nc == null) return null;
        return MeasuredAmount.cents(
          unitCents: nc - widget.currentUnitCostCents,
          quantity: widget.currentStock,
          quantityScale: MeasurementType.fromDb(
            widget.measurementType,
          ).quantityScale,
        );
      case InventoryAdjustmentType.openingBalance:
        return null;
    }
  }

  // ── Submit ─────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final service = sl<InventoryAdjustmentService>();
      await service.adjustForProduct(
        productId: widget.productId,
        variantId: widget.variantId,
        type: _type,
        quantityDelta: _signedDelta(),
        newUnitCostCents: _type == InventoryAdjustmentType.revaluation
            ? _newCostCents()
            : null,
        reason: _reasonCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  // ── UI ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(LucideIcons.boxes, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('inventory_adjustment.title'.tr())),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.subjectLabel != null) ...[
                  Text(
                    widget.subjectLabel!,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                ],
                _buildSummaryRow(cs),
                const SizedBox(height: 16),
                _buildTypeSelector(cs),
                const SizedBox(height: 16),
                if (_type != InventoryAdjustmentType.revaluation)
                  _buildQuantityField(cs),
                if (_type == InventoryAdjustmentType.revaluation)
                  _buildCostField(cs),
                const SizedBox(height: 12),
                _buildReasonField(),
                const SizedBox(height: 12),
                _buildNotesField(),
                const SizedBox(height: 16),
                _buildPreviewCard(cs),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _buildErrorBanner(cs, _error!),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.check, size: 16),
          label: Text('inventory_adjustment.post'.tr()),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _summaryChip(
            cs,
            'inventory_adjustment.current_stock'.tr(),
            localizedQuantity(widget.currentStock, widget.measurementType),
          ),
          const SizedBox(width: 12),
          _summaryChip(
            cs,
            'inventory_adjustment.unit_cost'.tr(),
            _fmtCents(widget.currentUnitCostCents),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(ColorScheme cs, String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSelector(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'inventory_adjustment.type'.tr(),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        SegmentedButton<InventoryAdjustmentType>(
          segments: [
            ButtonSegment(
              value: InventoryAdjustmentType.shrinkage,
              label: Text('inventory_adjustment.type_shrinkage'.tr()),
              icon: const Icon(LucideIcons.trendingDown, size: 16),
            ),
            ButtonSegment(
              value: InventoryAdjustmentType.gain,
              label: Text('inventory_adjustment.type_gain'.tr()),
              icon: const Icon(LucideIcons.trendingUp, size: 16),
            ),
            ButtonSegment(
              value: InventoryAdjustmentType.revaluation,
              label: Text('inventory_adjustment.type_revaluation'.tr()),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
            ),
          ],
          selected: {_type},
          onSelectionChanged: _submitting
              ? null
              : (s) => setState(() => _type = s.first),
        ),
        const SizedBox(height: 6),
        Text(
          _typeHelp(),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  String _typeHelp() {
    switch (_type) {
      case InventoryAdjustmentType.shrinkage:
        return 'inventory_adjustment.help_shrinkage'.tr();
      case InventoryAdjustmentType.gain:
        return 'inventory_adjustment.help_gain'.tr();
      case InventoryAdjustmentType.revaluation:
        return 'inventory_adjustment.help_revaluation'.tr();
      case InventoryAdjustmentType.openingBalance:
        return '';
    }
  }

  Widget _buildQuantityField(ColorScheme cs) {
    return TextFormField(
      controller: _qtyCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      onTap: () => selectAllText(_qtyCtrl),
      enabled: !_submitting,
      decoration: InputDecoration(
        labelText: 'inventory_adjustment.quantity'.tr(),
        helperText: 'inventory_adjustment.quantity_helper'.tr(),
        border: const OutlineInputBorder(),
        prefixIcon: Icon(
          _type == InventoryAdjustmentType.shrinkage
              ? LucideIcons.minus
              : LucideIcons.plus,
          size: 18,
        ),
        suffixIcon:
            MeasurementType.fromDb(widget.measurementType).minorUnit == null
            ? null
            : DropdownButtonHideUnderline(
                child: DropdownButton<MeasurementUnit>(
                  value: _quantityUnit,
                  isDense: true,
                  items: MeasurementType.fromDb(widget.measurementType)
                      .inputUnits
                      .map(
                        (unit) => DropdownMenuItem(
                          value: unit,
                          child: Text('measurement.units.${unit.dbValue}'.tr()),
                        ),
                      )
                      .toList(),
                  onChanged: (unit) {
                    if (unit == null) return;
                    final stored = _qty();
                    setState(() {
                      _quantityUnit = unit;
                      _qtyCtrl.text = MeasuredQuantity.editableValue(
                        stored,
                        unit,
                      );
                    });
                  },
                ),
              ),
      ),
      onChanged: (_) => setState(() {}),
      validator: (v) {
        final n = _qty();
        if (n <= 0) {
          return 'inventory_adjustment.quantity_invalid'.tr();
        }
        if (_type == InventoryAdjustmentType.shrinkage &&
            n > widget.currentStock) {
          return 'inventory_adjustment.quantity_exceeds_stock'.tr();
        }
        return null;
      },
    );
  }

  Widget _buildCostField(ColorScheme cs) {
    return TextFormField(
      controller: _costCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onTap: () => selectAllText(_costCtrl),
      enabled: !_submitting,
      decoration: InputDecoration(
        labelText: 'inventory_adjustment.new_unit_cost'.tr(),
        helperText: 'inventory_adjustment.cost_helper'.tr(),
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(LucideIcons.dollarSign, size: 18),
      ),
      onChanged: (_) => setState(() {}),
      validator: (v) {
        final c = _parseToCents(v ?? '');
        if (c == null || c < 0) {
          return 'inventory_adjustment.cost_invalid'.tr();
        }
        if (c == widget.currentUnitCostCents) {
          return 'inventory_adjustment.cost_unchanged'.tr();
        }
        if (widget.currentStock <= 0) {
          return 'inventory_adjustment.revaluation_requires_stock'.tr();
        }
        return null;
      },
    );
  }

  Widget _buildReasonField() {
    return TextFormField(
      controller: _reasonCtrl,
      enabled: !_submitting,
      maxLength: 120,
      decoration: InputDecoration(
        labelText: 'inventory_adjustment.reason'.tr(),
        helperText: 'inventory_adjustment.reason_helper'.tr(),
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(LucideIcons.messageSquare, size: 18),
      ),
      validator: (v) {
        if ((v ?? '').trim().isEmpty) {
          return 'inventory_adjustment.reason_required'.tr();
        }
        return null;
      },
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesCtrl,
      enabled: !_submitting,
      maxLines: 2,
      decoration: InputDecoration(
        labelText: 'inventory_adjustment.notes'.tr(),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildPreviewCard(ColorScheme cs) {
    final newStock = _newStockPreview();
    final val = _previewValueCents();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.eye, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                'inventory_adjustment.preview'.tr(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_type != InventoryAdjustmentType.revaluation)
            _previewLine(
              'inventory_adjustment.new_stock'.tr(),
              '${localizedQuantity(widget.currentStock, widget.measurementType)}  →  ${localizedQuantity(newStock, widget.measurementType)}',
              newStock < 0 ? cs.error : null,
            ),
          if (_type == InventoryAdjustmentType.revaluation)
            _previewLine(
              'inventory_adjustment.new_unit_cost'.tr(),
              '${_fmtCents(widget.currentUnitCostCents)}  →  ${_costCtrl.text}',
              null,
            ),
          if (val != null)
            _previewLine(
              'inventory_adjustment.value_impact'.tr(),
              _fmtCents(val.abs()),
              null,
            ),
          const SizedBox(height: 6),
          Text(
            _journalPreview(),
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewLine(String label, String value, Color? valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  String _journalPreview() {
    final val = _previewValueCents();
    switch (_type) {
      case InventoryAdjustmentType.shrinkage:
        return 'Dr 5800 Inventory Shrinkage / Cr 1200 Inventory';
      case InventoryAdjustmentType.gain:
        return 'Dr 1200 Inventory / Cr 4200 Inventory Gain';
      case InventoryAdjustmentType.revaluation:
        if (val == null) return '';
        return val >= 0
            ? 'Dr 1200 Inventory / Cr 5900 Inventory Revaluation'
            : 'Dr 5900 Inventory Revaluation / Cr 1200 Inventory';
      case InventoryAdjustmentType.openingBalance:
        return '';
    }
  }

  Widget _buildErrorBanner(ColorScheme cs, String message) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, size: 16, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
