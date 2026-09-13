import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/database/daos/cheque_instrument_dao.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/cheque_management_service.dart';
import '../../../../core/utils/app_date_formatter.dart';

Future<bool> showAccountChequeDialog(
  BuildContext context, {
  String? initialPartyType,
  int? initialPartyId,
  int? userId,
}) async {
  final service = sl<ChequeManagementService>();
  final allParties = await service.getAccountParties();
  if (!context.mounted) return false;

  final parties = allParties
      .where(
        (party) =>
            (initialPartyType == null ||
            (party.partyType == initialPartyType &&
                party.partyId == initialPartyId)),
      )
      .toList(growable: false);
  if (parties.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('cheques.no_account_parties'.tr())));
    return false;
  }

  ChequeAccountParty selected = parties.first;
  var direction = selected.suggestedDirection;
  final amount = TextEditingController(
    text: _suggestedAmount(selected, direction),
  );
  final number = TextEditingController();
  final bank = TextEditingController();
  final branch = TextEditingController();
  final account = TextEditingController();
  final drawer = TextEditingController();
  final note = TextEditingController();
  var issueDate = _today();
  var dueDate = _today();
  var saving = false;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => _AccountChequeControllerOwner(
      controllers: [amount, number, bank, branch, account, drawer, note],
      child: StatefulBuilder(
        builder: (context, setState) => AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.filePlus2),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'cheques.add_account_cheque'.tr(),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (initialPartyType == null)
                    DropdownButtonFormField<ChequeAccountParty>(
                      initialValue: selected,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'cheques.party'.tr(),
                        prefixIcon: const Icon(LucideIcons.userRound),
                      ),
                      items: parties
                          .map(
                            (party) => DropdownMenuItem(
                              value: party,
                              child: Text(
                                '${party.partyName} — ${_partyTypeLabel(party)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: saving
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() {
                                selected = value;
                                direction = value.suggestedDirection;
                                amount.text = _suggestedAmount(
                                  value,
                                  direction,
                                );
                              });
                            },
                    )
                  else
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(LucideIcons.userRound),
                      title: Text(selected.partyName),
                      subtitle: Text(_partyTypeLabel(selected)),
                    ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${'cheques.current_balance'.tr()}: ${selected.currencySymbol}${(selected.availableBalanceCents / 100).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                selected:
                                    direction == ChequeDirectionValue.incoming,
                                showCheckmark: true,
                                avatar: const Icon(
                                  LucideIcons.arrowDownLeft,
                                  size: 18,
                                ),
                                label: SizedBox(
                                  width: double.infinity,
                                  child: Text(
                                    'cheques.direction_incoming'.tr(),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                onSelected:
                                    saving ||
                                        !_hasDirection(
                                          parties,
                                          ChequeDirectionValue.incoming,
                                        )
                                    ? null
                                    : (_) {
                                        final party =
                                            selected.canUseDirection(
                                              ChequeDirectionValue.incoming,
                                            )
                                            ? selected
                                            : _firstPartyForDirection(
                                                parties,
                                                ChequeDirectionValue.incoming,
                                              );
                                        setState(() {
                                          direction =
                                              ChequeDirectionValue.incoming;
                                          selected = party;
                                          amount.text = _suggestedAmount(
                                            party,
                                            direction,
                                          );
                                        });
                                      },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                selected:
                                    direction == ChequeDirectionValue.outgoing,
                                showCheckmark: true,
                                avatar: const Icon(
                                  LucideIcons.arrowUpRight,
                                  size: 18,
                                ),
                                label: SizedBox(
                                  width: double.infinity,
                                  child: Text(
                                    'cheques.direction_outgoing'.tr(),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                onSelected:
                                    saving ||
                                        !_hasDirection(
                                          parties,
                                          ChequeDirectionValue.outgoing,
                                        )
                                    ? null
                                    : (_) {
                                        final party =
                                            selected.canUseDirection(
                                              ChequeDirectionValue.outgoing,
                                            )
                                            ? selected
                                            : _firstPartyForDirection(
                                                parties,
                                                ChequeDirectionValue.outgoing,
                                              );
                                        setState(() {
                                          direction =
                                              ChequeDirectionValue.outgoing;
                                          selected = party;
                                          amount.text = _suggestedAmount(
                                            party,
                                            direction,
                                          );
                                        });
                                      },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    enabled: !saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'cheques.amount'.tr(),
                      suffixText: selected.currencyCode,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: number,
                    enabled: !saving,
                    decoration: InputDecoration(
                      labelText: 'cheques.number'.tr(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: bank,
                    enabled: !saving,
                    decoration: InputDecoration(labelText: 'cheques.bank'.tr()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: branch,
                    enabled: !saving,
                    decoration: InputDecoration(
                      labelText: 'cheques.branch'.tr(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: account,
                    enabled: !saving,
                    decoration: InputDecoration(
                      labelText: 'cheques.account_number'.tr(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: drawer,
                    enabled: !saving,
                    decoration: InputDecoration(
                      labelText: 'cheques.drawer'.tr(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    enabled: !saving,
                    maxLines: 2,
                    decoration: InputDecoration(labelText: 'cheques.note'.tr()),
                  ),
                  const SizedBox(height: 8),
                  _AccountChequeDateRow(
                    issueDate: issueDate,
                    dueDate: dueDate,
                    enabled: !saving,
                    onIssueDate: (date) => setState(() => issueDate = date),
                    onDueDate: (date) => setState(() => dueDate = date),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'cheques.account_cheque_pending_notice'.tr(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(sheetContext, false),
                          child: Text('common.cancel'.tr()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  try {
                                    setState(() => saving = true);
                                    await service.createAccountCheque(
                                      party: selected,
                                      direction: direction,
                                      amountCents: _parseCents(amount.text),
                                      chequeNumber: number.text,
                                      issueDate: issueDate,
                                      dueDate: dueDate,
                                      bankName: bank.text,
                                      branchName: branch.text,
                                      accountNumber: account.text,
                                      drawerName: drawer.text,
                                      note: note.text,
                                      userId: userId,
                                    );
                                    if (sheetContext.mounted) {
                                      Navigator.pop(sheetContext, true);
                                    }
                                  } catch (error) {
                                    if (!sheetContext.mounted) return;
                                    setState(() => saving = false);
                                    ScaffoldMessenger.of(
                                      sheetContext,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          _accountChequeError(error),
                                        ),
                                      ),
                                    );
                                  }
                                },
                          icon: saving
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(LucideIcons.save),
                          label: Text('common.save'.tr()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  return result ?? false;
}

/// Owns the field controllers for the complete lifetime of the modal route.
///
/// The future returned by [showModalBottomSheet] completes when the route is
/// popped, before its reverse transition has necessarily finished. Disposing
/// the controllers after awaiting that future can therefore leave transition
/// widgets listening to already-disposed notifiers. Keeping disposal inside
/// the sheet element makes it happen only when Flutter removes that element.
class _AccountChequeControllerOwner extends StatefulWidget {
  final List<TextEditingController> controllers;
  final Widget child;

  const _AccountChequeControllerOwner({
    required this.controllers,
    required this.child,
  });

  @override
  State<_AccountChequeControllerOwner> createState() =>
      _AccountChequeControllerOwnerState();
}

class _AccountChequeControllerOwnerState
    extends State<_AccountChequeControllerOwner> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AccountChequeDateRow extends StatelessWidget {
  final DateTime issueDate;
  final DateTime dueDate;
  final bool enabled;
  final ValueChanged<DateTime> onIssueDate;
  final ValueChanged<DateTime> onDueDate;

  const _AccountChequeDateRow({
    required this.issueDate,
    required this.dueDate,
    required this.enabled,
    required this.onIssueDate,
    required this.onDueDate,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final issue = _dateButton(
        context,
        label: 'cheques.issue_date'.tr(),
        date: issueDate,
        onDate: onIssueDate,
      );
      final due = _dateButton(
        context,
        label: 'cheques.due_date'.tr(),
        date: dueDate,
        onDate: onDueDate,
      );
      if (constraints.maxWidth < 380) {
        return Column(children: [issue, due]);
      }
      return Row(
        children: [
          Expanded(child: issue),
          const SizedBox(width: 8),
          Expanded(child: due),
        ],
      );
    },
  );

  Widget _dateButton(
    BuildContext context, {
    required String label,
    required DateTime date,
    required ValueChanged<DateTime> onDate,
  }) => ListTile(
    enabled: enabled,
    contentPadding: EdgeInsets.zero,
    leading: const Icon(LucideIcons.calendar),
    title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(AppDateFormatter.date(date)),
    onTap: !enabled
        ? null
        : () async {
            final selected = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2000),
              lastDate: DateTime(2200),
            );
            if (selected != null) onDate(selected);
          },
  );
}

String _partyTypeLabel(ChequeAccountParty party) =>
    'cheques.party_${party.partyType}'.tr();

bool _hasDirection(List<ChequeAccountParty> parties, String direction) =>
    parties.any((party) => party.canUseDirection(direction));

ChequeAccountParty _firstPartyForDirection(
  List<ChequeAccountParty> parties,
  String direction,
) => parties.firstWhere((party) => party.canUseDirection(direction));

String _suggestedAmount(ChequeAccountParty party, String direction) {
  final cents = party.suggestedAmountFor(direction);
  return cents == 0 ? '' : (cents / 100).toStringAsFixed(2);
}

int _parseCents(String raw) {
  try {
    final value = Decimal.parse(raw.trim().replaceAll(',', '.'));
    final scaled = value * Decimal.fromInt(100);
    if (value <= Decimal.zero || !scaled.isInteger) {
      throw const FormatException();
    }
    return scaled.toBigInt().toInt();
  } on FormatException {
    throw ArgumentError('cheque_amount_invalid');
  }
}

String _accountChequeError(Object error) {
  final raw = error.toString();
  const keys = [
    'cheque_number_required',
    'cheque_amount_invalid',
    'cheque_due_before_issue',
    'cheque_number_duplicate',
    'cheque_party_not_found',
    'account_cheque_direction_mismatch',
    'account_cheque_exceeds_balance',
  ];
  for (final key in keys) {
    if (raw.contains(key)) return 'cheques.error_$key'.tr();
  }
  return 'cheques.action_failed'.tr(args: [raw]);
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}
