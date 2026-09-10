import 'package:easy_localization/easy_localization.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/cheque_confirmation_dao.dart';
import '../../../../core/database/daos/cheque_instrument_dao.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/cheque_lifecycle_service.dart';
import '../../../../core/services/cheque_management_service.dart';
import '../../../../core/utils/app_date_formatter.dart';
import '../../../auth/auth.dart';
import '../services/cheque_instrument_pdf_service.dart';

enum _ChequeAction {
  edit,
  printDocument,
  shareDocument,
  deposit,
  clear,
  bounce,
  resolve,
  cancel,
  source,
}

class ChequeManagementScreen extends StatefulWidget {
  final String initialStatus;

  const ChequeManagementScreen({super.key, this.initialStatus = 'open'});

  @override
  State<ChequeManagementScreen> createState() => _ChequeManagementScreenState();
}

class _ChequeManagementScreenState extends State<ChequeManagementScreen> {
  final _search = TextEditingController();
  late final ChequeManagementService _management;
  late final ChequeLifecycleService _lifecycle;
  String _direction = 'all';
  late String _status;

  int? get _userId {
    final state = context.read<AuthBloc>().state;
    return state is AuthAuthenticated ? state.user.id : null;
  }

  @override
  void initState() {
    super.initState();
    _management = sl<ChequeManagementService>();
    _lifecycle = sl<ChequeLifecycleService>();
    _status = widget.initialStatus;
    _search.addListener(_refresh);
  }

  @override
  void dispose() {
    _search
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('cheques.title'.tr()),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).canPop()
              ? Navigator.of(context).pop()
              : context.go('/dashboard'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreatePartialDialog,
        icon: const Icon(LucideIcons.filePlus2),
        label: Text('cheques.add_partial'.tr()),
      ),
      body: StreamBuilder<List<ChequeRegisterEntry>>(
        stream: _management.watchRegister(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error.toString());
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          final visible = _applyFilters(all);
          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(all)),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyView(hasAny: all.isNotEmpty),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _ChequeCard(
                        entry: visible[index],
                        onAction: (action) =>
                            _handleAction(visible[index], action),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(List<ChequeRegisterEntry> entries) {
    final open = entries
        .where((e) => ChequeInstrumentStatus.open.contains(e.instrument.status))
        .toList();
    final overdue = open
        .where((e) => e.instrument.dueDate.isBefore(_today()))
        .length;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryCard(
                label: 'cheques.incoming_open'.tr(),
                value: open
                    .where(
                      (e) =>
                          e.instrument.direction ==
                          ChequeDirectionValue.incoming,
                    )
                    .length
                    .toString(),
                color: Colors.green,
                icon: LucideIcons.arrowDownLeft,
              ),
              _SummaryCard(
                label: 'cheques.outgoing_open'.tr(),
                value: open
                    .where(
                      (e) =>
                          e.instrument.direction ==
                          ChequeDirectionValue.outgoing,
                    )
                    .length
                    .toString(),
                color: Colors.orange,
                icon: LucideIcons.arrowUpRight,
              ),
              _SummaryCard(
                label: 'cheques.overdue'.tr(),
                value: overdue.toString(),
                color: Colors.red,
                icon: LucideIcons.triangleAlert,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(LucideIcons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _search.clear,
                      icon: const Icon(Icons.clear),
                    ),
              hintText: 'cheques.search'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final value in const ['all', 'incoming', 'outgoing'])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(
                      selected: _direction == value,
                      label: Text('cheques.direction_$value'.tr()),
                      onSelected: (_) => setState(() => _direction = value),
                    ),
                  ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final value in const [
                  'open',
                  'cleared',
                  'bounced',
                  'cancelled',
                  'all',
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(
                      selected: _status == value,
                      label: Text('cheques.status_filter_$value'.tr()),
                      onSelected: (_) => setState(() => _status = value),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<ChequeRegisterEntry> _applyFilters(List<ChequeRegisterEntry> rows) {
    final query = _search.text.trim().toLowerCase();
    return rows
        .where((entry) {
          final c = entry.instrument;
          if (_direction != 'all' && c.direction != _direction) return false;
          if (_status == 'open' &&
              !ChequeInstrumentStatus.open.contains(c.status)) {
            return false;
          }
          if (_status != 'all' && _status != 'open' && c.status != _status) {
            return false;
          }
          if (query.isEmpty) return true;
          return [
            c.chequeNumber,
            c.bankName,
            c.accountNumber,
            entry.referenceNumber,
            entry.partyName,
          ].whereType<String>().any(
            (value) => value.toLowerCase().contains(query),
          );
        })
        .toList(growable: false);
  }

  Future<void> _handleAction(
    ChequeRegisterEntry entry,
    _ChequeAction action,
  ) async {
    try {
      switch (action) {
        case _ChequeAction.edit:
          await _showEditDialog(entry);
        case _ChequeAction.printDocument:
          await ChequeInstrumentPdfService.printDocument(
            context: context,
            entry: entry,
          );
        case _ChequeAction.shareDocument:
          await ChequeInstrumentPdfService.shareDocument(
            context: context,
            entry: entry,
          );
        case _ChequeAction.deposit:
          await _lifecycle.markDeposited(
            sourceTable: entry.instrument.sourceTable,
            sourceId: entry.instrument.sourceId,
            instrumentId: entry.instrument.id,
            userId: _userId,
          );
          _success('cheques.deposited'.tr());
        case _ChequeAction.clear:
          if (!_hasRequiredIdentity(entry.instrument)) {
            await _showEditDialog(entry);
            return;
          }
          final confirmed = await _confirm(
            'cheques.clear_title'.tr(),
            'cheques.clear_confirm'.tr(),
          );
          if (!confirmed) return;
          await _lifecycle.markCleared(
            sourceTable: entry.instrument.sourceTable,
            sourceId: entry.instrument.sourceId,
            instrumentId: entry.instrument.id,
            userId: _userId,
          );
          _success('cheques.cleared'.tr());
        case _ChequeAction.bounce:
          final reason = await _askBounceReason();
          if (reason == null) return;
          await _lifecycle.markBounced(
            sourceTable: entry.instrument.sourceTable,
            sourceId: entry.instrument.sourceId,
            instrumentId: entry.instrument.id,
            bounceReason: reason,
            userId: _userId,
          );
          _success('cheques.bounced'.tr());
        case _ChequeAction.resolve:
          await _showResolutionDialog(entry);
        case _ChequeAction.cancel:
          final confirmed = await _confirm(
            'cheques.cancel_title'.tr(),
            'cheques.cancel_confirm'.tr(),
          );
          if (!confirmed) return;
          await _lifecycle.markCancelled(
            sourceTable: entry.instrument.sourceTable,
            sourceId: entry.instrument.sourceId,
            instrumentId: entry.instrument.id,
            userId: _userId,
          );
          _success('cheques.cancelled'.tr());
        case _ChequeAction.source:
          _openSource(entry.instrument);
      }
    } catch (error) {
      _failure(_errorMessage(error));
    }
  }

  bool _hasRequiredIdentity(ChequeInstrument instrument) =>
      instrument.chequeNumber?.trim().isNotEmpty == true;

  Future<void> _showResolutionDialog(ChequeRegisterEntry entry) async {
    final incoming =
        entry.instrument.direction == ChequeDirectionValue.incoming;
    final options = <String>[
      ChequeResolutionType.cash,
      ChequeResolutionType.bank,
      ChequeResolutionType.card,
      ChequeResolutionType.replacement,
      ChequeResolutionType.credit,
      if (incoming) ChequeResolutionType.writeOff,
    ];
    final note = TextEditingController();
    final number = TextEditingController();
    final bank = TextEditingController();
    var selected = ChequeResolutionType.cash;
    var issueDate = DateTime.now();
    var dueDate = DateTime.now().add(const Duration(days: 30));

    final input = await showDialog<_ChequeResolutionInput>(
      context: context,
      builder: (dialogContext) => _DialogControllerScope(
        controllers: [note, number, bank],
        builder: (context, setDialogState) => AlertDialog(
          title: Text('cheques.resolve_title'.tr()),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'cheques.resolve_summary'.tr(
                      args: [
                        entry.instrument.chequeNumber ??
                            '#${entry.instrument.id}',
                        _money(
                          entry.instrument.amountCents.toBigInt().toInt(),
                          entry.currencySymbol,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    decoration: InputDecoration(
                      labelText: 'cheques.resolution_method'.tr(),
                    ),
                    items: options
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('cheques.resolution_$value'.tr()),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selected = value);
                      }
                    },
                  ),
                  if (selected == ChequeResolutionType.credit) ...[
                    const SizedBox(height: 10),
                    Text(
                      'cheques.credit_resolution_hint'.tr(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (selected == ChequeResolutionType.writeOff) ...[
                    const SizedBox(height: 10),
                    Text(
                      'cheques.write_off_warning'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (selected == ChequeResolutionType.replacement) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: number,
                      decoration: InputDecoration(
                        labelText: 'cheques.replacement_number'.tr(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: bank,
                      decoration: InputDecoration(
                        labelText: 'cheques.replacement_bank'.tr(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('cheques.issue_date'.tr()),
                      subtitle: Text(AppDateFormatter.date(issueDate)),
                      trailing: const Icon(Icons.calendar_month_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: issueDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() => issueDate = picked);
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('cheques.due_date'.tr()),
                      subtitle: Text(AppDateFormatter.date(dueDate)),
                      trailing: const Icon(Icons.event_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: dueDate,
                          firstDate: issueDate,
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() => dueDate = picked);
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'cheques.resolution_note'.tr(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () {
                if (selected == ChequeResolutionType.replacement &&
                    number.text.trim().isEmpty) {
                  _failure('cheques.error_replacement_details_required'.tr());
                  return;
                }
                Navigator.pop(
                  context,
                  _ChequeResolutionInput(
                    type: selected,
                    note: note.text,
                    replacementNumber: number.text,
                    replacementBank: bank.text,
                    replacementIssueDate: issueDate,
                    replacementDueDate: dueDate,
                  ),
                );
              },
              child: Text('cheques.confirm_resolution'.tr()),
            ),
          ],
        ),
      ),
    );
    if (input == null || !mounted) return;
    await _lifecycle.resolveBounced(
      instrumentId: entry.instrument.id,
      resolutionType: input.type,
      note: input.note,
      replacementChequeNumber: input.type == ChequeResolutionType.replacement
          ? input.replacementNumber
          : null,
      replacementBankName: input.type == ChequeResolutionType.replacement
          ? input.replacementBank
          : null,
      replacementIssueDate: input.type == ChequeResolutionType.replacement
          ? input.replacementIssueDate
          : null,
      replacementDueDate: input.type == ChequeResolutionType.replacement
          ? input.replacementDueDate
          : null,
      userId: _userId,
    );
    _success('cheques.resolution_saved'.tr());
  }

  Future<void> _showCreatePartialDialog() async {
    final docs = await _management.watchOutstandingDocuments().first;
    if (!mounted) return;
    if (docs.isEmpty) {
      _failure('cheques.no_outstanding'.tr());
      return;
    }
    ChequeOutstandingDocument? selected = docs.first;
    final amount = TextEditingController(
      text: (selected.outstandingCents / 100).toStringAsFixed(2),
    );
    final number = TextEditingController();
    final bank = TextEditingController();
    final branch = TextEditingController();
    final account = TextEditingController();
    final drawer = TextEditingController();
    final note = TextEditingController();
    var issueDate = _today();
    var dueDate = _today();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _DialogControllerScope(
        controllers: [amount, number, bank, branch, account, drawer, note],
        builder: (context, setDialogState) => AlertDialog(
          title: Text('cheques.add_partial'.tr()),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<ChequeOutstandingDocument>(
                    initialValue: selected,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'cheques.document'.tr(),
                    ),
                    items: docs
                        .map(
                          (doc) => DropdownMenuItem(
                            value: doc,
                            child: Text(
                              '${doc.referenceNumber} — ${doc.partyName ?? 'cheques.no_party'.tr()} — ${_money(doc.outstandingCents, doc.currencySymbol)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selected = value;
                        amount.text = (value.outstandingCents / 100)
                            .toStringAsFixed(2);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'cheques.amount'.tr(),
                      suffixText: selected?.currencyCode,
                      helperText: 'cheques.outstanding_limit'.tr(
                        args: [
                          _money(
                            selected!.outstandingCents,
                            selected!.currencySymbol,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ChequeFields(
                    number: number,
                    bank: bank,
                    branch: branch,
                    account: account,
                    drawer: drawer,
                    note: note,
                  ),
                  _DateRow(
                    issueDate: issueDate,
                    dueDate: dueDate,
                    onIssueDate: (date) =>
                        setDialogState(() => issueDate = date),
                    onDueDate: (date) => setDialogState(() => dueDate = date),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton.icon(
              onPressed: () async {
                try {
                  final cents = _parseCents(amount.text);
                  await _management.createPartialCheque(
                    document: selected!,
                    amountCents: cents,
                    chequeNumber: number.text,
                    issueDate: issueDate,
                    dueDate: dueDate,
                    bankName: bank.text,
                    branchName: branch.text,
                    accountNumber: account.text,
                    drawerName: drawer.text,
                    note: note.text,
                    userId: _userId,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text(_errorMessage(error)),
                        backgroundColor: Theme.of(
                          dialogContext,
                        ).colorScheme.error,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(LucideIcons.save),
              label: Text('common.save'.tr()),
            ),
          ],
        ),
      ),
    );
    if (saved == true) _success('cheques.partial_created'.tr());
  }

  Future<void> _showEditDialog(ChequeRegisterEntry entry) async {
    final c = entry.instrument;
    final number = TextEditingController(text: c.chequeNumber);
    final bank = TextEditingController(text: c.bankName);
    final branch = TextEditingController(text: c.branchName);
    final account = TextEditingController(text: c.accountNumber);
    final drawer = TextEditingController(text: c.drawerName);
    final note = TextEditingController(text: c.note);
    var issueDate = c.issueDate ?? c.createdAt;
    var dueDate = c.dueDate;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _DialogControllerScope(
        controllers: [number, bank, branch, account, drawer, note],
        builder: (context, setDialogState) => AlertDialog(
          title: Text('cheques.details'.tr()),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.referenceNumber),
                    subtitle: Text(
                      '${entry.partyName ?? 'cheques.no_party'.tr()} • ${_money(c.amountCents.toBigInt().toInt(), entry.currencySymbol)}',
                    ),
                  ),
                  _ChequeFields(
                    number: number,
                    bank: bank,
                    branch: branch,
                    account: account,
                    drawer: drawer,
                    note: note,
                  ),
                  _DateRow(
                    issueDate: issueDate,
                    dueDate: dueDate,
                    onIssueDate: (date) =>
                        setDialogState(() => issueDate = date),
                    onDueDate: (date) => setDialogState(() => dueDate = date),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await _management.updateDetails(
                    entry: entry,
                    chequeNumber: number.text,
                    issueDate: issueDate,
                    dueDate: dueDate,
                    bankName: bank.text,
                    branchName: branch.text,
                    accountNumber: account.text,
                    drawerName: drawer.text,
                    note: note.text,
                    userId: _userId,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text(_errorMessage(error))),
                    );
                  }
                }
              },
              child: Text('common.save'.tr()),
            ),
          ],
        ),
      ),
    );
    if (saved == true) _success('cheques.details_saved'.tr());
  }

  Future<String?> _askBounceReason() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _DialogControllerScope(
        controllers: [controller],
        builder: (context, _) => AlertDialog(
          title: Text('cheques.bounce_title'.tr()),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'cheques.bounce_reason'.tr(),
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
              child: Text('common.confirm'.tr()),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('common.no'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('common.yes'.tr()),
            ),
          ],
        ),
      ) ??
      false;

  void _openSource(ChequeInstrument instrument) {
    final path = switch (instrument.sourceTable) {
      ChequeSourceTables.sale => '/sales/${instrument.sourceId}',
      ChequeSourceTables.purchase => '/purchases/${instrument.sourceId}',
      ChequeSourceTables.saleReturn => '/sales/returns/${instrument.sourceId}',
      ChequeSourceTables.purchaseReturn =>
        '/purchases/returns/${instrument.sourceId}',
      ChequeSourceTables.saleReturnAdjustment =>
        '/sales/returns/adj/${instrument.sourceId}',
      ChequeSourceTables.purchaseReturnAdjustment =>
        '/purchases/returns/adj/${instrument.sourceId}',
      _ => null,
    };
    if (path != null) context.push(path);
  }

  int _parseCents(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    try {
      final value = Decimal.parse(normalized);
      final scaled = value * Decimal.fromInt(100);
      if (value <= Decimal.zero || !scaled.isInteger) {
        throw const FormatException();
      }
      return scaled.toBigInt().toInt();
    } on FormatException {
      throw ArgumentError('cheque_amount_invalid');
    }
  }

  String _errorMessage(Object error) {
    final raw = error.toString();
    if (raw.contains('replacement_cheque_details_required')) {
      return 'cheques.error_replacement_details_required'.tr();
    }
    const keys = [
      'cheque_number_required',
      'cheque_amount_invalid',
      'cheque_due_before_issue',
      'cheque_amount_exceeds_outstanding',
      'cheque_number_duplicate',
      'cheque_source_not_found',
      'cheque_not_found',
      'cheque_not_bounced',
      'cheque_already_resolved',
      'cheque_party_required',
      'outgoing_cheque_cannot_be_written_off',
      'cheque_dishonoured_balance_mismatch',
      'cheque_resolution_source_unsupported',
    ];
    for (final key in keys) {
      if (raw.contains(key)) return 'cheques.error_$key'.tr();
    }
    return 'cheques.action_failed'.tr(args: [raw]);
  }

  void _success(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green.shade700),
    );
  }

  void _failure(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

/// Owns text controllers for a dialog and disposes them only when the dialog
/// route has actually left the widget tree. A `showDialog` future completes
/// when `pop` is requested, before the reverse transition has necessarily
/// finished, so disposing controllers immediately after awaiting it can make
/// the still-animating text fields use disposed notifiers.
class _DialogControllerScope extends StatefulWidget {
  final List<TextEditingController> controllers;
  final Widget Function(BuildContext context, StateSetter setState) builder;

  const _DialogControllerScope({
    required this.controllers,
    required this.builder,
  });

  @override
  State<_DialogControllerScope> createState() => _DialogControllerScopeState();
}

class _DialogControllerScopeState extends State<_DialogControllerScope> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      StatefulBuilder(builder: widget.builder);
}

class _ChequeCard extends StatelessWidget {
  final ChequeRegisterEntry entry;
  final ValueChanged<_ChequeAction> onAction;

  const _ChequeCard({required this.entry, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final c = entry.instrument;
    final incoming = c.direction == ChequeDirectionValue.incoming;
    final open = ChequeInstrumentStatus.open.contains(c.status);
    final overdue = open && c.dueDate.isBefore(_today());
    final color = overdue
        ? Colors.red
        : incoming
        ? Colors.green
        : Colors.orange;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onAction(_ChequeAction.edit),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withAlpha(28),
                    foregroundColor: color,
                    child: Icon(
                      incoming
                          ? LucideIcons.arrowDownLeft
                          : LucideIcons.arrowUpRight,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.chequeNumber?.trim().isNotEmpty == true
                              ? '${'cheques.cheque_number_short'.tr()} ${c.chequeNumber}'
                              : 'cheques.number_missing'.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${entry.referenceNumber} • ${entry.partyName ?? 'cheques.no_party'.tr()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _money(
                      c.amountCents.toBigInt().toInt(),
                      entry.currencySymbol,
                    ),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  PopupMenuButton<_ChequeAction>(
                    onSelected: onAction,
                    itemBuilder: (_) => _actionsFor(c)
                        .map(
                          (action) => PopupMenuItem(
                            value: action,
                            child: Text(_actionLabel(action)),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Tag(
                    text: 'cheques.status_${c.status}'.tr(),
                    color: _statusColor(c.status),
                  ),
                  _Tag(
                    text:
                        '${'cheques.due'.tr()}: ${AppDateFormatter.date(c.dueDate)}',
                    color: overdue ? Colors.red : Colors.blueGrey,
                  ),
                  if (c.bankName?.trim().isNotEmpty == true)
                    _Tag(text: c.bankName!, color: Colors.indigo),
                  if (c.resolutionType != null)
                    _Tag(
                      text: 'cheques.resolution_${c.resolutionType}'.tr(),
                      color: Colors.green,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static List<_ChequeAction> _actionsFor(ChequeInstrument c) {
    final actions = <_ChequeAction>[
      _ChequeAction.edit,
      _ChequeAction.printDocument,
      _ChequeAction.shareDocument,
      _ChequeAction.source,
    ];
    if (c.direction == ChequeDirectionValue.incoming &&
        c.status == ChequeInstrumentStatus.received) {
      actions.add(_ChequeAction.deposit);
    }
    if (ChequeInstrumentStatus.open.contains(c.status)) {
      actions.addAll([
        _ChequeAction.clear,
        _ChequeAction.bounce,
        _ChequeAction.cancel,
      ]);
    }
    if (c.status == ChequeInstrumentStatus.bounced && c.resolvedAt == null) {
      actions.add(_ChequeAction.resolve);
    }
    return actions;
  }

  static String _actionLabel(_ChequeAction action) => switch (action) {
    _ChequeAction.edit => 'cheques.edit_details'.tr(),
    _ChequeAction.printDocument => 'cheques.print_document'.tr(),
    _ChequeAction.shareDocument => 'cheques.share_document'.tr(),
    _ChequeAction.deposit => 'cheques.mark_deposited'.tr(),
    _ChequeAction.clear => 'cheques.bank_reconcile'.tr(),
    _ChequeAction.bounce => 'cheques.mark_bounced'.tr(),
    _ChequeAction.resolve => 'cheques.resolve_bounced'.tr(),
    _ChequeAction.cancel => 'cheques.cancel'.tr(),
    _ChequeAction.source => 'cheques.open_document'.tr(),
  };
}

class _ChequeResolutionInput {
  final String type;
  final String note;
  final String replacementNumber;
  final String replacementBank;
  final DateTime replacementIssueDate;
  final DateTime replacementDueDate;

  const _ChequeResolutionInput({
    required this.type,
    required this.note,
    required this.replacementNumber,
    required this.replacementBank,
    required this.replacementIssueDate,
    required this.replacementDueDate,
  });
}

class _ChequeFields extends StatelessWidget {
  final TextEditingController number;
  final TextEditingController bank;
  final TextEditingController branch;
  final TextEditingController account;
  final TextEditingController drawer;
  final TextEditingController note;

  const _ChequeFields({
    required this.number,
    required this.bank,
    required this.branch,
    required this.account,
    required this.drawer,
    required this.note,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(
        controller: number,
        decoration: InputDecoration(labelText: 'cheques.number'.tr()),
      ),
      TextField(
        controller: bank,
        decoration: InputDecoration(labelText: 'cheques.bank'.tr()),
      ),
      TextField(
        controller: branch,
        decoration: InputDecoration(labelText: 'cheques.branch'.tr()),
      ),
      TextField(
        controller: account,
        decoration: InputDecoration(labelText: 'cheques.account_number'.tr()),
      ),
      TextField(
        controller: drawer,
        decoration: InputDecoration(labelText: 'cheques.drawer'.tr()),
      ),
      TextField(
        controller: note,
        maxLines: 2,
        decoration: InputDecoration(labelText: 'cheques.note'.tr()),
      ),
      const SizedBox(height: 8),
    ],
  );
}

class _DateRow extends StatelessWidget {
  final DateTime issueDate;
  final DateTime dueDate;
  final ValueChanged<DateTime> onIssueDate;
  final ValueChanged<DateTime> onDueDate;

  const _DateRow({
    required this.issueDate,
    required this.dueDate,
    required this.onIssueDate,
    required this.onDueDate,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final issue = _DateButton(
        label: 'cheques.issue_date'.tr(),
        date: issueDate,
        onDate: onIssueDate,
      );
      final due = _DateButton(
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
}

class _DateButton extends StatelessWidget {
  final String label;
  final DateTime date;
  final ValueChanged<DateTime> onDate;

  const _DateButton({
    required this.label,
    required this.date,
    required this.onDate,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(LucideIcons.calendar),
    title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(AppDateFormatter.date(date)),
    onTap: () async {
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

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;

  const _Tag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withAlpha(24),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
    ),
  );
}

class _EmptyView extends StatelessWidget {
  final bool hasAny;
  const _EmptyView({required this.hasAny});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.fileCheck2, size: 56),
          const SizedBox(height: 12),
          Text(
            hasAny ? 'cheques.no_results'.tr() : 'cheques.empty'.tr(),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text('cheques.action_failed'.tr(args: [error])),
    ),
  );
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String _money(int cents, String symbol) =>
    NumberFormat.currency(symbol: symbol, decimalDigits: 2).format(cents / 100);

Color _statusColor(String status) => switch (status) {
  ChequeInstrumentStatus.cleared => Colors.green,
  ChequeInstrumentStatus.bounced => Colors.red,
  ChequeInstrumentStatus.cancelled => Colors.grey,
  ChequeInstrumentStatus.deposited => Colors.blue,
  _ => Colors.orange,
};
