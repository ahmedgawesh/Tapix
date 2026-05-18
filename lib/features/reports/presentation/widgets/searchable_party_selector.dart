import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';

/// A generic option used by [SearchablePartySelector]. Adapt your domain
/// option type into one of these before passing into the selector.
class SearchablePartyOption {
  final int id;
  final String name;
  final String? phone;
  final int balanceCents;

  const SearchablePartyOption({
    required this.id,
    required this.name,
    required this.phone,
    required this.balanceCents,
  });
}

/// A searchable selector that replaces a plain `DropdownButtonFormField` for
/// customer / supplier pickers in the reports section.
///
/// Tapping the field opens a bottom sheet with a search input that filters
/// options by **name** or **phone** (case-insensitive, accent-insensitive
/// for digits). The visible field mirrors the original dropdown styling so
/// existing screen layouts are preserved.
class SearchablePartySelector extends StatelessWidget {
  final List<SearchablePartyOption> options;
  final int? selectedId;
  final ValueChanged<int?> onChanged;
  final String labelText;
  final IconData prefixIcon;

  const SearchablePartySelector({
    super.key,
    required this.options,
    required this.selectedId,
    required this.onChanged,
    required this.labelText,
    this.prefixIcon = LucideIcons.user,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    final selected = selectedId == null
        ? null
        : options.cast<SearchablePartyOption?>().firstWhere(
              (o) => o!.id == selectedId,
              orElse: () => null,
            );

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _openPicker(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: labelText,
          prefixIcon: Icon(prefixIcon, color: colorScheme.primary),
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        isEmpty: selected == null,
        child: selected == null
            ? const SizedBox.shrink()
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      selected.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    cs.formatCents(selected.balanceCents),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: selected.balanceCents > 0
                          ? colorScheme.error
                          : colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final result = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _PartyPickerSheet(
        options: options,
        selectedId: selectedId,
        labelText: labelText,
        prefixIcon: prefixIcon,
      ),
    );
    if (result != null) {
      // result == -1 means "cleared"
      onChanged(result == -1 ? null : result);
    }
  }
}

class _PartyPickerSheet extends StatefulWidget {
  final List<SearchablePartyOption> options;
  final int? selectedId;
  final String labelText;
  final IconData prefixIcon;

  const _PartyPickerSheet({
    required this.options,
    required this.selectedId,
    required this.labelText,
    required this.prefixIcon,
  });

  @override
  State<_PartyPickerSheet> createState() => _PartyPickerSheetState();
}

class _PartyPickerSheetState extends State<_PartyPickerSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<SearchablePartyOption> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    // Only digits → match phone strictly by digit substring.
    final digitsOnly = RegExp(r'^\d+$').hasMatch(q);
    return widget.options.where((o) {
      final nameMatch = o.name.toLowerCase().contains(q);
      final phone = (o.phone ?? '').toLowerCase();
      // For phone matching, also strip non-digits so '0123-456' finds '0123456'.
      final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
      final phoneMatch = phone.contains(q) ||
          (digitsOnly && phoneDigits.contains(q));
      return nameMatch || phoneMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();
    final filtered = _filtered;
    final mediaQuery = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(
                children: [
                  Icon(widget.prefixIcon, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.labelText,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (widget.selectedId != null)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(-1),
                      icon: const Icon(LucideIcons.x, size: 16),
                      label: Text('common.clear'.tr()),
                    ),
                ],
              ),
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'reports.search_party_hint'.tr(),
                  prefixIcon: const Icon(LucideIcons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(LucideIcons.x, size: 18),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.searchX,
                              size: 40,
                              color: colorScheme.onSurfaceVariant),
                          const SizedBox(height: 8),
                          Text('common.no_results'.tr(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final o = filtered[index];
                        final selected = o.id == widget.selectedId;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: selected
                                ? colorScheme.primary
                                : colorScheme.surfaceContainerHighest,
                            child: Icon(
                              widget.prefixIcon,
                              size: 18,
                              color: selected
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                          title: Text(
                            o.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: (o.phone != null && o.phone!.isNotEmpty)
                              ? Row(
                                  children: [
                                    Icon(LucideIcons.phone,
                                        size: 12,
                                        color:
                                            colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        o.phone!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant),
                                      ),
                                    ),
                                  ],
                                )
                              : null,
                          trailing: Text(
                            cs.formatCents(o.balanceCents),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: o.balanceCents > 0
                                  ? colorScheme.error
                                  : colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          selected: selected,
                          onTap: () => Navigator.of(context).pop(o.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
