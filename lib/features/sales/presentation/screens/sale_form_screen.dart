import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:decimal/decimal.dart';

import '../../../../core/database/app_database.dart' show Customer, Employee;
import '../../../../core/di/injection_container.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/services/currency_service.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../products/domain/entities/product_variant_entity.dart';
import '../../../products/domain/repositories/product_color_repository.dart';
import '../../../products/domain/repositories/size_repository.dart';
import '../../../products/presentation/bloc/products_bloc.dart';
import '../../../products/presentation/bloc/variant_previews_bloc.dart';
import '../../../products/presentation/bloc/product_variants_bloc.dart';
import '../../../customers/domain/repositories/customer_repository.dart';
import '../../../customers/presentation/bloc/customers_bloc.dart';
import '../../../employees/domain/repositories/employee_repository.dart';
import '../bloc/sale_form_bloc.dart';

part 'sale_form_dialogs.dart';

class SaleFormScreen extends StatelessWidget {
  final int? saleId;
  const SaleFormScreen({super.key, this.saleId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SaleFormBloc>()
        ..add(SaleFormInitialized(saleId: saleId, currencyId: 1)),
      child: const _SaleFormView(),
    );
  }
}

class _SaleFormView extends StatefulWidget {
  const _SaleFormView();
  @override
  State<_SaleFormView> createState() => _SaleFormViewState();
}

class _SaleFormViewState extends State<_SaleFormView> {
  final _notesCtrl = TextEditingController();
  final _taxCtrl = TextEditingController(text: '0');

  @override
  void dispose() {
    _notesCtrl.dispose();
    _taxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final curr = sl<CurrencyService>();

    return BlocConsumer<SaleFormBloc, SaleFormState>(
      listenWhen: (p, c) => p.isSuccess != c.isSuccess || p.error != c.error,
      listener: (context, state) {
        if (state.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('sales.saved_success'.tr())));
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/sales');
          }
        }
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.error!), backgroundColor: cs.error));
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/sales');
                }
              },
            ),
            title: Text(state.saleId == null ? 'sales.new'.tr() : 'sales.edit'.tr()),
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _customerCard(context, state, theme, cs),
                    const SizedBox(height: 12),
                    _employeeCard(context, state, theme, cs),
                    const SizedBox(height: 12),
                    _dateCard(context, state, theme, cs),
                    const SizedBox(height: 12),
                    _discountToggle(context, state, theme, cs),
                    const SizedBox(height: 16),
                    _itemsHeader(context, state, theme, cs),
                    const SizedBox(height: 8),
                    if (state.items.isEmpty) _emptyHint(theme, cs),
                    ...state.items.map((i) => _itemTile(context, i, theme, cs, curr)),
                    const SizedBox(height: 16),
                    _totalsCard(state, theme, cs, curr),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
              _bottomBar(context, state, theme, cs, curr),
            ],
          ),
        );
      },
    );
  }

  Widget _pickerCard(ColorScheme cs, ThemeData theme, {
    required Color bgColor, required IconData icon, required Color iconColor,
    required String label, required String value, bool hasValue = false,
    VoidCallback? onClear, required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(width: 40, height: 40,
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                color: hasValue ? null : cs.onSurfaceVariant)),
            ])),
            if (onClear != null) IconButton(
              icon: Icon(LucideIcons.x, size: 16, color: cs.onSurfaceVariant),
              onPressed: onClear, visualDensity: VisualDensity.compact),
            Icon(LucideIcons.chevronRight, size: 18, color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }

  Widget _customerCard(BuildContext ctx, SaleFormState s, ThemeData t, ColorScheme cs) =>
    _pickerCard(cs, t, bgColor: cs.primaryContainer, icon: LucideIcons.user,
      iconColor: cs.onPrimaryContainer, label: 'sales.customer'.tr(),
      value: s.customerName ?? 'sales.walk_in'.tr(), hasValue: s.customerId != null,
      onClear: s.customerId != null ? () => ctx.read<SaleFormBloc>().add(const SaleCustomerChanged()) : null,
      onTap: () => _showCustomerPicker(ctx));

  Widget _employeeCard(BuildContext ctx, SaleFormState s, ThemeData t, ColorScheme cs) {
    final has = s.employeeId != null && s.employeeId != 0;
    return _pickerCard(cs, t, bgColor: cs.tertiaryContainer, icon: LucideIcons.userCheck,
      iconColor: cs.onTertiaryContainer, label: 'sales.salesperson'.tr(),
      value: has ? (s.employeeName ?? '') : 'sales.select_salesperson'.tr(), hasValue: has,
      onClear: has ? () => ctx.read<SaleFormBloc>().add(const SaleEmployeeChanged()) : null,
      onTap: () => _showEmployeePicker(ctx));
  }

  Widget _dateCard(BuildContext ctx, SaleFormState s, ThemeData t, ColorScheme cs) =>
    _pickerCard(cs, t, bgColor: cs.secondaryContainer, icon: LucideIcons.calendar,
      iconColor: cs.onSecondaryContainer, label: 'sales.date'.tr(),
      value: DateFormat.yMMMd().format(s.saleDate), hasValue: true,
      onTap: () async {
        final d = await showDatePicker(context: ctx, initialDate: s.saleDate,
          firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 30)));
        if (d != null && ctx.mounted) ctx.read<SaleFormBloc>().add(SaleDateChanged(d));
      });

  Widget _discountToggle(BuildContext ctx, SaleFormState s, ThemeData t, ColorScheme cs) => Row(
    children: [
      Icon(LucideIcons.tag, size: 16, color: cs.primary), const SizedBox(width: 8),
      Text('sales.discount_mode'.tr(), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      const Spacer(),
      SegmentedButton<SaleDiscountMode>(
        segments: [
          ButtonSegment(value: SaleDiscountMode.perItem, label: Text('sales.per_item'.tr(), style: const TextStyle(fontSize: 12))),
          ButtonSegment(value: SaleDiscountMode.invoice, label: Text('sales.invoice'.tr(), style: const TextStyle(fontSize: 12))),
        ],
        selected: {s.discountMode},
        onSelectionChanged: (v) => ctx.read<SaleFormBloc>().add(SaleDiscountModeChanged(v.first)),
        style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ),
    ],
  );

  Widget _itemsHeader(BuildContext ctx, SaleFormState s, ThemeData t, ColorScheme cs) => Row(
    children: [
      Icon(LucideIcons.shoppingCart, size: 18, color: cs.primary), const SizedBox(width: 8),
      Text('sales.items'.tr(), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      if (s.items.isNotEmpty) ...[const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
          child: Text('${s.items.length}', style: t.textTheme.labelSmall?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold)))],
      const Spacer(),
      FilledButton.tonalIcon(
        onPressed: () => _showAddItemSheet(ctx),
        icon: const Icon(LucideIcons.plus, size: 16),
        label: Text('sales.add_item'.tr()),
        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap)),
    ],
  );

  Widget _emptyHint(ThemeData t, ColorScheme cs) => Container(
    padding: const EdgeInsets.all(32), margin: const EdgeInsets.only(top: 8),
    decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3))),
    child: Center(child: Column(children: [
      Icon(LucideIcons.packageOpen, size: 40, color: cs.onSurface.withValues(alpha: 0.15)),
      const SizedBox(height: 8),
      Text('sales.no_items_hint'.tr(), style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
    ])),
  );

  Widget _itemTile(BuildContext ctx, SaleLineItem item, ThemeData t, ColorScheme cs, CurrencyService curr) {
    final hasImage = item.product.imagePath != null && item.product.imagePath!.isNotEmpty;
    return Card(
      elevation: 0, margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showEditItemSheet(ctx, item),
        child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              image: hasImage
                  ? DecorationImage(
                      image: FileImage(File(item.product.imagePath!)),
                      fit: BoxFit.cover,
                      onError: (exception, stackTrace) {},
                    )
                  : null,
            ),
            child: !hasImage
                ? Icon(LucideIcons.package, size: 20, color: cs.onSurfaceVariant)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.displayName, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            if (item.colorHex != null || item.sizeName != null) _variantChips(item, cs),
            Row(children: [
              Text('${item.quantity} × ${curr.format(item.unitPriceCents.toBigInt().toInt())}',
                style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              if (item.discountCents > Decimal.zero) ...[const SizedBox(width: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(6)),
                  child: Text('-${curr.format(item.discountCents.toBigInt().toInt())}',
                    style: t.textTheme.labelSmall?.copyWith(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600)))],
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(curr.format(item.totalCents.toBigInt().toInt()),
              style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
            const SizedBox(height: 4),
            InkWell(onTap: () => ctx.read<SaleFormBloc>().add(SaleLineItemRemoved(item.tempId)),
              borderRadius: BorderRadius.circular(8),
              child: Padding(padding: const EdgeInsets.all(4),
                child: Icon(LucideIcons.trash2, size: 16, color: cs.error))),
          ]),
        ])),
      ),
    );
  }

  Widget _variantChips(SaleLineItem item, ColorScheme cs) {
    final colorHex = item.colorHex?.trim();
    final shade = _tryParseHexColor(colorHex);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (shade != null) _colorDotChip(cs, shade),
          if (item.sizeName != null && item.sizeName!.isNotEmpty) _chip(cs, item.sizeName!),
        ],
      ),
    );
  }

  Color? _tryParseHexColor(String? hex) {
    if (hex == null) return null;
    final cleaned = hex.trim().replaceFirst('#', '');
    if (cleaned.isEmpty) return null;

    final buffer = StringBuffer();
    if (cleaned.length == 6) buffer.write('FF');
    buffer.write(cleaned);

    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return null;
    }
  }

  Widget _colorDotChip(ColorScheme cs, Color shade) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Center(
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: shade,
            shape: BoxShape.circle,
            border: Border.all(color: cs.outline.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }

  Widget _chip(ColorScheme cs, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(6),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5))),
    child: Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)));

  Widget _totalsCard(SaleFormState s, ThemeData t, ColorScheme cs, CurrencyService curr) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3))),
      child: Column(children: [
        _row(t, 'sales.subtotal'.tr(), curr.format(s.subtotalCents.toBigInt().toInt())),
        if (s.totalDiscountCents > Decimal.zero) ...[const SizedBox(height: 8),
          _row(t, 'sales.discount'.tr(), '- ${curr.format(s.totalDiscountCents.toBigInt().toInt())}', valueColor: cs.tertiary)],
        if (s.taxCents > Decimal.zero) ...[const SizedBox(height: 8),
          _row(t, 'sales.tax'.tr(), curr.format(s.taxCents.toBigInt().toInt()))],
        Divider(height: 20, color: cs.outlineVariant.withValues(alpha: 0.5)),
        _row(t, 'sales.total'.tr(), curr.format(s.totalCents.toBigInt().toInt()), isBold: true, valueColor: cs.primary),
      ]),
    );
  }

  Widget _row(ThemeData t, String l, String v, {bool isBold = false, Color? valueColor}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(l, style: (isBold ? t.textTheme.titleSmall : t.textTheme.bodyMedium)?.copyWith(
        color: isBold ? null : t.colorScheme.onSurfaceVariant)),
      Text(v, style: (isBold ? t.textTheme.titleMedium : t.textTheme.bodyMedium)?.copyWith(
        color: valueColor, fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
    ]);

  Widget _bottomBar(BuildContext ctx, SaleFormState s, ThemeData t, ColorScheme cs, CurrencyService curr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
        boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, -2))]),
      child: SafeArea(child: Row(children: [
        Expanded(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('sales.total'.tr(), style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          Text(curr.format(s.totalCents.toBigInt().toInt()),
            style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
          Text('${s.totalQuantity} ${'sales.items'.tr().toLowerCase()}',
            style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ])),
        const SizedBox(width: 12),
        Expanded(child: FilledButton.icon(
          onPressed: s.items.isEmpty ? null : () => _showCheckoutDialog(ctx, s, curr),
          icon: const Icon(LucideIcons.shoppingBag, size: 18),
          label: Text('sales.checkout'.tr()),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)))),
      ])),
    );
  }

  // Dialog launchers
  void _showCustomerPicker(BuildContext ctx) {
    final bloc = ctx.read<SaleFormBloc>();
    showModalBottomSheet<void>(context: ctx, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sc) => _CustomerPickerSheet(onSelected: (c) {
        bloc.add(SaleCustomerChanged(customerId: c.id, customerName: c.name));
        Navigator.pop(sc);
      }));
  }

  void _showEmployeePicker(BuildContext ctx) {
    final bloc = ctx.read<SaleFormBloc>();
    showModalBottomSheet<void>(context: ctx, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sc) => _EmployeePickerSheet(onSelected: (e) {
        bloc.add(SaleEmployeeChanged(employeeId: e.id, employeeName: e.name));
        Navigator.pop(sc);
      }));
  }

  void _showAddItemSheet(BuildContext ctx) {
    final bloc = ctx.read<SaleFormBloc>();
    showModalBottomSheet<void>(context: ctx, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sc) => MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => sl<ProductsBloc>()..add(const ProductSearchRequested(''))),
          BlocProvider(create: (_) => sl<VariantPreviewsBloc>()),
        ],
        child: _AddItemSheet(onItemAdded: (product, variant, qty, price) {
          bloc.add(SaleLineItemAdded(product: product, variant: variant, quantity: qty, unitPriceCents: price));
          Navigator.pop(sc);
        })));
  }

  void _showEditItemSheet(BuildContext ctx, SaleLineItem item) {
    final bloc = ctx.read<SaleFormBloc>();
    showModalBottomSheet<void>(context: ctx, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sc) => _EditItemSheet(item: item,
        onUpdated: (qty, price, discount) {
          bloc.add(SaleLineItemUpdated(tempId: item.tempId, quantity: qty, unitPriceCents: price, discountCents: discount));
          Navigator.pop(sc);
        },
        onRemoved: () { bloc.add(SaleLineItemRemoved(item.tempId)); Navigator.pop(sc); }));
  }

  void _showCheckoutDialog(BuildContext ctx, SaleFormState s, CurrencyService curr) {
    final bloc = ctx.read<SaleFormBloc>();
    showModalBottomSheet<void>(context: ctx, isScrollControlled: true, useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sc) => BlocProvider.value(value: bloc,
        child: _CheckoutSheet(currencyService: curr, notesCtrl: _notesCtrl, taxCtrl: _taxCtrl,
          onConfirm: () { bloc.add(const SaleFormSubmitted()); Navigator.pop(sc); })));
  }
}
