import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../bloc/suppliers_bloc.dart';

/// Always visible, including when there are no active suppliers.
class SupplierStatusFilterBar extends StatelessWidget {
  const SupplierStatusFilterBar({
    super.key,
    required this.selected,
    required this.activeCount,
    required this.inactiveCount,
    required this.totalCount,
    required this.onChanged,
  });

  final SupplierStatusFilter selected;
  final int activeCount;
  final int inactiveCount;
  final int totalCount;
  final ValueChanged<SupplierStatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(SupplierStatusFilter.active, activeCount),
        _chip(SupplierStatusFilter.inactive, inactiveCount),
        _chip(SupplierStatusFilter.all, totalCount),
      ],
    );
  }

  Widget _chip(SupplierStatusFilter filter, int count) => ChoiceChip(
    key: ValueKey('supplier_status_${filter.name}'),
    label: Text('${'suppliers.filter_${filter.name}'.tr()} ($count)'),
    selected: selected == filter,
    onSelected: (_) => onChanged(filter),
  );
}
