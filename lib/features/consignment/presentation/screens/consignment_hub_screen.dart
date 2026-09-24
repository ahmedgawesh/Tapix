import 'package:drift/drift.dart' hide Column;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/money/money_input_parser.dart';
import '../../../../core/measurement/measurement.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/business/local_branch_scope.dart';
import '../../../../core/services/business/warehouse_operation_scope.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/inventory/inventory_stock_source_service.dart';
import '../../data/consignment_agreement_import_service.dart';
import '../../data/consignment_agreement_service.dart';
import '../../data/consignment_module_service.dart';
import '../../data/consignment_receipt_service.dart';
import '../../data/consignment_ownership_conversion_service.dart';
import '../../data/consignment_custody_service.dart';
import '../../data/consignment_reporting_service.dart';
import '../../data/consignment_settlement_service.dart';
import '../services/consignment_report_export_service.dart';
import '../widgets/consignment_help.dart';
import '../widgets/consignment_reason_dialog.dart';

class ConsignmentHubScreen extends StatefulWidget {
  const ConsignmentHubScreen({super.key});

  @override
  State<ConsignmentHubScreen> createState() => _ConsignmentHubScreenState();
}

class _ConsignmentHubScreenState extends State<ConsignmentHubScreen> {
  int _section = 0;
  late Future<ConsignmentDashboardSnapshot> _future = _load();

  Future<ConsignmentDashboardSnapshot> _load() =>
      sl<ConsignmentReportingService>().load();

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('consignment.saved'.tr())));
    } catch (error) {
      if (!mounted) return;
      final message = error is ConsignmentUserException
          ? error.messageKey.tr()
          : 'consignment.operation_failed'.tr();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/suppliers'),
          icon: const Icon(LucideIcons.arrowLeft),
          tooltip: 'common.back'.tr(),
        ),
        title: Text('consignment.title'.tr()),
        actions: [
          IconButton(
            onPressed: () => showConsignmentGuide(context),
            icon: const Icon(Icons.help_outline),
            tooltip: 'consignment.guide_title'.tr(),
          ),
          IconButton(
            onPressed: _refresh,
            icon: const Icon(LucideIcons.refreshCw),
            tooltip: 'common.refresh'.tr(),
          ),
        ],
      ),
      body: FutureBuilder<ConsignmentDashboardSnapshot>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _AccessOrError(error: snapshot.error, retry: _refresh);
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _hero(context, data)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SectionHeaderDelegate(
                    child: _sectionSelector(context),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  sliver: SliverToBoxAdapter(child: _body(context, data)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _hero(BuildContext context, ConsignmentDashboardSnapshot data) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 170),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.primaryContainer, colors.tertiaryContainer],
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.packageCheck, color: colors.primary, size: 32),
                const SizedBox(height: 12),
                Text(
                  'consignment.hero_title'.tr(),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'consignment.hero_desc'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            );
            final stats = Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HeroMetric(
                  label: 'consignment.stock_in_custody'.tr(),
                  value: localizedQuantityTotals(data.supplierOwnedQuantities),
                ),
                _HeroMetric(
                  label: 'consignment.unsettled'.tr(),
                  value: _localizedMoneyTotals(
                    data.unsettledObligationsByCurrency,
                  ),
                ),
                _HeroMetric(
                  label: 'consignment.payable'.tr(),
                  value: _localizedMoneyTotals(
                    data.outstandingPayablesByCurrency,
                  ),
                ),
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [copy, const SizedBox(height: 20), stats],
              );
            }
            return Row(
              children: [
                Expanded(flex: 3, child: copy),
                const SizedBox(width: 24),
                Expanded(flex: 2, child: stats),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionSelector(BuildContext context) {
    const icons = [
      LucideIcons.layoutDashboard,
      LucideIcons.fileSignature,
      LucideIcons.packagePlus,
      LucideIcons.packageMinus,
      LucideIcons.receiptText,
      LucideIcons.chartNoAxesCombined,
    ];
    final labels = [
      'consignment.overview'.tr(),
      'consignment.agreements'.tr(),
      'consignment.receipts'.tr(),
      'consignment.custody_movements'.tr(),
      'consignment.settlements'.tr(),
      'consignment.report'.tr(),
    ];
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SegmentedButton<int>(
          segments: [
            for (var index = 0; index < labels.length; index++)
              ButtonSegment(
                value: index,
                icon: Icon(icons[index], size: 18),
                label: Text(labels[index]),
              ),
          ],
          selected: {_section},
          onSelectionChanged: (selection) =>
              setState(() => _section = selection.single),
          showSelectedIcon: false,
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ConsignmentDashboardSnapshot data) {
    return switch (_section) {
      0 => _Overview(
        data: data,
        onNewAgreement: () => _newAgreement(data),
        onNewReceipt: () => _newReceipt(data),
        onNewConversion: () => _newConversion(data),
        onNewCustody: () => _newCustody(data),
        onNewSettlement: () => _newSettlement(data),
        onOpenReport: () => setState(() => _section = 5),
      ),
      1 => _AgreementsSection(
        data: data,
        onCreate: () => _newAgreement(data),
        onActivate: (id) =>
            _run(() async => sl<ConsignmentAgreementService>().activate(id)),
        onClose: _closeAgreement,
        onRevise: _reviseAgreement,
      ),
      2 => _ReceiptsSection(
        data: data,
        onCreate: () => _newReceipt(data),
        onConvert: () => _newConversion(data),
        onVoidConversion: _voidConversion,
        onPost: (id) => _run(
          () async => sl<ConsignmentReceiptService>().post(
            receiptId: id,
            requestKey: const Uuid().v4(),
          ),
        ),
        onVoid: _voidReceipt,
      ),
      3 => _CustodySection(
        data: data,
        onCreate: () => _newCustody(data),
        onPost: (id) => _run(
          () async => sl<ConsignmentCustodyService>().post(
            documentId: id,
            requestKey: const Uuid().v4(),
          ),
        ),
        onVoid: _voidCustody,
      ),
      4 => _SettlementsSection(
        data: data,
        onCreate: () => _newSettlement(data),
        onReview: (id) =>
            _run(() async => sl<ConsignmentSettlementService>().review(id)),
        onPost: (id) =>
            _run(() async => sl<ConsignmentSettlementService>().post(id)),
        onPay: (statement) => _pay(
          statement,
          data.currencyCodes[statement.currencyId] ??
              sl<CurrencyService>().currencyCode,
        ),
        onPayments: (statement) => _showPayments(statement, data),
        onVoid: (statement) => _void(statement),
      ),
      _ => _ConsignmentReport(data: data),
    };
  }

  Future<void> _newAgreement(ConsignmentDashboardSnapshot data) async {
    final input = await showModalBottomSheet<_AgreementInput>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => const _AgreementSheet(),
    );
    if (input == null) return;
    await _run(() async {
      await sl<AppDatabase>().transaction(() async {
        final service = sl<ConsignmentAgreementService>();
        final draft = await service.createDraftOrRevision(
          supplierId: input.supplierId,
          currencyId: input.currencyId,
          agreementNumber: input.number,
          effectiveFrom: input.effectiveFrom,
          settlementFrequency: input.frequency,
          paymentTermsDays: input.paymentTermsDays,
          settlementTaxRateBps: input.taxRateBps,
          settlementTaxInclusive: input.taxInclusive,
          notes: input.notes,
          terms: input.terms,
        );
        await service.setSupplierDefaultMode(
          input.supplierId,
          input.supplierMode,
        );
        if (input.activate) await service.activate(draft.id);
      });
    });
  }

  Future<void> _reviseAgreement(ConsignmentAgreement agreement) async {
    final input = await showModalBottomSheet<_AgreementInput>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _AgreementSheet(existing: agreement),
    );
    if (input == null) return;
    await _run(() async {
      await sl<AppDatabase>().transaction(() async {
        final service = sl<ConsignmentAgreementService>();
        final revision = await service.revise(
          activeAgreementId: agreement.id,
          agreementNumber: input.number,
          effectiveFrom: input.effectiveFrom,
          settlementFrequency: input.frequency,
          paymentTermsDays: input.paymentTermsDays,
          settlementTaxRateBps: input.taxRateBps,
          settlementTaxInclusive: input.taxInclusive,
          notes: input.notes,
          terms: input.terms,
        );
        await service.setSupplierDefaultMode(
          input.supplierId,
          input.supplierMode,
        );
        if (input.activate) await service.activate(revision.id);
      });
    });
  }

  Future<void> _closeAgreement(String agreementId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('consignment.close_agreement'.tr()),
        content: Text('consignment.close_agreement_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('common.confirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () async => sl<ConsignmentAgreementService>().close(agreementId),
    );
  }

  Future<void> _newReceipt(ConsignmentDashboardSnapshot data) async {
    final input = await showModalBottomSheet<_ReceiptInput>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _ReceiptSheet(data: data),
    );
    if (input == null) return;
    await _run(() async {
      final agreement = data.agreements.firstWhere(
        (row) => row.id == input.agreementId,
      );
      final scope = await LocalBranchScope.read(sl<AppDatabase>());
      final service = sl<ConsignmentReceiptService>();
      final draft = await service.createDraft(
        requestKey: const Uuid().v4(),
        receiptNumber: input.number,
        warehouseId: scope.warehouseId,
        supplierId: agreement.supplierId,
        agreementId: agreement.id,
        currencyId: agreement.currencyId,
        receivedAt: input.receivedAt,
        notes: input.notes,
        lines: input.lines,
      );
      if (input.post) {
        await service.post(receiptId: draft.id, requestKey: const Uuid().v4());
      }
    });
  }

  Future<void> _newConversion(ConsignmentDashboardSnapshot data) async {
    final input = await showModalBottomSheet<_ConversionInput>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _ConversionSheet(data: data),
    );
    if (input == null) return;
    await _run(() async {
      final agreement = data.agreements.firstWhere(
        (row) => row.id == input.agreementId,
      );
      final scope = await LocalBranchScope.read(sl<AppDatabase>());
      await sl<ConsignmentOwnershipConversionService>().convert(
        requestKey: const Uuid().v4(),
        conversionNumber: input.number,
        evidenceReference: input.evidenceReference,
        warehouseId: scope.warehouseId,
        supplierId: agreement.supplierId,
        agreementId: agreement.id,
        currencyId: agreement.currencyId,
        convertedAt: input.convertedAt,
        notes: input.notes,
        lines: input.lines,
      );
    });
  }

  Future<void> _voidConversion(int conversionId) async {
    final reason = await showConsignmentReasonDialog(
      context,
      title: 'consignment.void_conversion'.tr(),
      label: 'consignment.void_reason'.tr(),
      cancelLabel: 'common.cancel'.tr(),
      confirmLabel: 'common.confirm'.tr(),
    );
    if (reason == null) return;
    await _run(
      () async => sl<ConsignmentOwnershipConversionService>().voidConversion(
        conversionId: conversionId,
        requestKey: const Uuid().v4(),
        reason: reason,
      ),
    );
  }

  Future<void> _voidReceipt(String receiptId) async {
    final reason = await showConsignmentReasonDialog(
      context,
      title: 'consignment.void_receipt'.tr(),
      label: 'consignment.void_reason'.tr(),
      cancelLabel: 'common.cancel'.tr(),
      confirmLabel: 'common.confirm'.tr(),
    );
    if (reason == null) return;
    await _run(
      () async => sl<ConsignmentReceiptService>().voidReceipt(
        receiptId: receiptId,
        requestKey: const Uuid().v4(),
        reason: reason,
      ),
    );
  }

  Future<void> _newCustody(ConsignmentDashboardSnapshot data) async {
    final input = await showModalBottomSheet<_CustodyInput>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _CustodySheet(data: data),
    );
    if (input == null) return;
    await _run(() async {
      final agreement = data.agreements.firstWhere(
        (row) => row.id == input.agreementId,
      );
      final scope = await LocalBranchScope.read(sl<AppDatabase>());
      final service = sl<ConsignmentCustodyService>();
      final draft = await service.createDraft(
        requestKey: const Uuid().v4(),
        documentNumber: input.number,
        documentType: input.type,
        responsibility: input.responsibility,
        warehouseId: scope.warehouseId,
        supplierId: agreement.supplierId,
        agreementId: agreement.id,
        currencyId: agreement.currencyId,
        occurredAt: input.occurredAt,
        reason: input.reason,
        notes: input.notes,
        lines: input.lines,
      );
      if (input.post) {
        await service.post(documentId: draft.id, requestKey: const Uuid().v4());
      }
    });
  }

  Future<void> _voidCustody(int documentId) async {
    final reason = await showConsignmentReasonDialog(
      context,
      title: 'consignment.void_custody'.tr(),
      label: 'consignment.void_reason'.tr(),
      cancelLabel: 'common.cancel'.tr(),
      confirmLabel: 'common.confirm'.tr(),
    );
    if (reason == null) return;
    await _run(
      () async => sl<ConsignmentCustodyService>().voidDocument(
        documentId: documentId,
        requestKey: const Uuid().v4(),
        reason: reason,
      ),
    );
  }

  Future<void> _newSettlement(ConsignmentDashboardSnapshot data) async {
    final input = await showModalBottomSheet<_SettlementInput>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _SettlementSheet(data: data),
    );
    if (input == null) return;
    await _run(() async {
      await sl<ConsignmentSettlementService>().createDraft(
        requestKey: const Uuid().v4(),
        agreementId: input.agreementId,
        periodStart: input.start,
        periodEnd: input.end,
        notes: input.notes,
      );
    });
  }

  Future<void> _pay(
    ConsignmentSettlementStatement statement,
    String currencyCode,
  ) async {
    final input = await showDialog<_PaymentInput>(
      context: context,
      builder: (context) =>
          _PaymentDialog(statement: statement, currencyCode: currencyCode),
    );
    if (input == null) return;
    await _run(() async {
      await sl<ConsignmentSettlementService>().recordPayment(
        statementId: statement.id,
        amountCents: input.amountCents,
        paymentMethod: input.method,
        requestKey: const Uuid().v4(),
        reference: input.reference,
      );
    });
  }

  Future<void> _showPayments(
    ConsignmentSettlementStatement statement,
    ConsignmentDashboardSnapshot data,
  ) async {
    final payments = data.payments
        .where((payment) => payment.statementId == statement.id)
        .toList();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('consignment.payments'.tr()),
        content: SizedBox(
          width: 520,
          child: payments.isEmpty
              ? Text('consignment.no_payments'.tr())
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: payments.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final payment = payments[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        sl<CurrencyService>().formatForCode(
                          payment.amountCents,
                          data.currencyCodes[statement.currencyId] ??
                              sl<CurrencyService>().currencyCode,
                        ),
                      ),
                      subtitle: Text(
                        '${'consignment.payment_${payment.paymentMethod}'.tr()} · '
                        '${DateFormat.yMd(context.locale.toString()).format(payment.paidAt.toLocal())}'
                        '${payment.reference.isEmpty ? '' : ' · ${payment.reference}'}',
                      ),
                      trailing: payment.status == 'posted'
                          ? TextButton.icon(
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                _reversePayment(payment);
                              },
                              icon: const Icon(LucideIcons.undo2),
                              label: Text('consignment.reverse_payment'.tr()),
                            )
                          : Chip(
                              label: Text(
                                'consignment.status_${payment.status}'.tr(),
                              ),
                            ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('common.close'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _reversePayment(ConsignmentSettlementPayment payment) async {
    final reason = await showConsignmentReasonDialog(
      context,
      title: 'consignment.reverse_payment'.tr(),
      label: 'consignment.reversal_reason'.tr(),
      cancelLabel: 'common.cancel'.tr(),
      confirmLabel: 'common.confirm'.tr(),
    );
    if (reason == null) return;
    await _run(
      () async => sl<ConsignmentSettlementService>().reversePayment(
        paymentId: payment.id,
        reason: reason,
      ),
    );
  }

  Future<void> _void(ConsignmentSettlementStatement statement) async {
    final reason = await showConsignmentReasonDialog(
      context,
      title: 'consignment.void_statement'.tr(),
      label: 'consignment.void_reason'.tr(),
      cancelLabel: 'common.cancel'.tr(),
      confirmLabel: 'common.confirm'.tr(),
    );
    if (reason == null) return;
    await _run(() async {
      await sl<ConsignmentSettlementService>().voidStatement(
        statementId: statement.id,
        reason: reason,
      );
    });
  }
}

class _AccessOrError extends StatelessWidget {
  const _AccessOrError({required this.error, required this.retry});
  final Object? error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    final denied =
        error is ConsignmentAccessDenied || error is ConsignmentModuleDisabled;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                denied ? LucideIcons.lockKeyhole : LucideIcons.triangleAlert,
                size: 52,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                denied
                    ? 'consignment.unavailable_title'.tr()
                    : 'common.error'.tr(),
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                denied
                    ? 'consignment.unavailable_desc'.tr()
                    : 'consignment.operation_failed'.tr(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: retry,
                icon: const Icon(LucideIcons.refreshCw),
                label: Text('common.retry'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.data,
    required this.onNewAgreement,
    required this.onNewReceipt,
    required this.onNewConversion,
    required this.onNewCustody,
    required this.onNewSettlement,
    required this.onOpenReport,
  });
  final ConsignmentDashboardSnapshot data;
  final VoidCallback onNewAgreement;
  final VoidCallback onNewReceipt;
  final VoidCallback onNewConversion;
  final VoidCallback onNewCustody;
  final VoidCallback onNewSettlement;
  final VoidCallback onOpenReport;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _ActionCard(
        icon: LucideIcons.filePlus2,
        title: 'consignment.new_agreement'.tr(),
        subtitle: 'consignment.new_agreement_desc'.tr(),
        onTap: data.operationsEnabled ? onNewAgreement : null,
      ),
      _ActionCard(
        icon: LucideIcons.packagePlus,
        title: 'consignment.new_receipt'.tr(),
        subtitle: 'consignment.new_receipt_desc'.tr(),
        onTap: data.operationsEnabled ? onNewReceipt : null,
      ),
      _ActionCard(
        icon: LucideIcons.repeat2,
        title: 'consignment.new_ownership_conversion'.tr(),
        subtitle: 'consignment.new_ownership_conversion_desc'.tr(),
        onTap: data.operationsEnabled ? onNewConversion : null,
      ),
      _ActionCard(
        icon: LucideIcons.packageMinus,
        title: 'consignment.new_custody_movement'.tr(),
        subtitle: 'consignment.new_custody_movement_desc'.tr(),
        onTap: data.operationsEnabled ? onNewCustody : null,
      ),
      _ActionCard(
        icon: LucideIcons.receiptText,
        title: 'consignment.new_settlement'.tr(),
        subtitle: 'consignment.new_settlement_desc'.tr(),
        onTap: data.historicalManagementEnabled ? onNewSettlement : null,
      ),
      _ActionCard(
        icon: LucideIcons.chartNoAxesCombined,
        title: 'consignment.report'.tr(),
        subtitle: 'consignment.report_desc'.tr(),
        onTap: onOpenReport,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ConsignmentHelpCard(
          messageKey: 'consignment.guide_overview_notice',
        ),
        const SizedBox(height: 16),
        Text(
          'consignment.quick_actions'.tr(),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1000
                ? 4
                : constraints.maxWidth >= 600
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final action in actions)
                  SizedBox(width: width, child: action),
              ],
            );
          },
        ),
        if (!data.operationsEnabled) ...[
          const SizedBox(height: 20),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListTile(
              leading: const Icon(LucideIcons.pauseCircle),
              title: Text('consignment.history_only_title'.tr()),
              subtitle: Text('consignment.history_only_desc'.tr()),
            ),
          ),
        ],
        const SizedBox(height: 28),
        _SafetyNote(),
      ],
    );
  }
}

class _AgreementsSection extends StatelessWidget {
  const _AgreementsSection({
    required this.data,
    required this.onCreate,
    required this.onActivate,
    required this.onClose,
    required this.onRevise,
  });
  final ConsignmentDashboardSnapshot data;
  final VoidCallback onCreate;
  final ValueChanged<String> onActivate;
  final ValueChanged<String> onClose;
  final ValueChanged<ConsignmentAgreement> onRevise;

  @override
  Widget build(BuildContext context) => _SectionScaffold(
    title: 'consignment.agreements'.tr(),
    actionLabel: 'consignment.new_agreement'.tr(),
    onAction: data.operationsEnabled ? onCreate : null,
    empty: data.agreements.isEmpty,
    children: [
      for (final row in data.agreements)
        _RecordCard(
          icon: LucideIcons.fileSignature,
          title: '${row.agreementNumber} · v${row.revision}',
          subtitle:
              '${data.suppliers[row.supplierId]?.name ?? '#${row.supplierId}'}\n'
              '${_date(row.effectiveFrom)} · ${'consignment.frequency_${row.settlementFrequency}'.tr()}',
          status: row.status,
          trailing: Wrap(
            spacing: 6,
            children: [
              if (row.status == 'draft')
                FilledButton.tonal(
                  onPressed: data.operationsEnabled
                      ? () => onActivate(row.id)
                      : null,
                  child: Text('consignment.activate'.tr()),
                ),
              if (row.status == 'active') ...[
                IconButton(
                  onPressed: data.operationsEnabled
                      ? () => onRevise(row)
                      : null,
                  icon: const Icon(LucideIcons.filePenLine),
                  tooltip: 'consignment.revise_agreement'.tr(),
                ),
                IconButton(
                  onPressed: () => onClose(row.id),
                  icon: const Icon(LucideIcons.archive),
                  tooltip: 'consignment.close_agreement'.tr(),
                ),
              ],
            ],
          ),
        ),
    ],
  );
}

class _ReceiptsSection extends StatelessWidget {
  const _ReceiptsSection({
    required this.data,
    required this.onCreate,
    required this.onConvert,
    required this.onVoidConversion,
    required this.onPost,
    required this.onVoid,
  });
  final ConsignmentDashboardSnapshot data;
  final VoidCallback onCreate;
  final VoidCallback onConvert;
  final ValueChanged<int> onVoidConversion;
  final ValueChanged<String> onPost;
  final ValueChanged<String> onVoid;

  @override
  Widget build(BuildContext context) => _SectionScaffold(
    title: 'consignment.receipts'.tr(),
    actionLabel: 'consignment.new_receipt'.tr(),
    onAction: data.operationsEnabled ? onCreate : null,
    empty: data.receipts.isEmpty && data.ownershipConversions.isEmpty,
    children: [
      const ConsignmentHelpCard(
        messageKey: 'consignment.guide_conversion_notice',
      ),
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FilledButton.tonalIcon(
          onPressed: data.operationsEnabled ? onConvert : null,
          icon: const Icon(LucideIcons.repeat2),
          label: Text('consignment.new_ownership_conversion'.tr()),
        ),
      ),
      const SizedBox(height: 12),
      for (final row in data.ownershipConversions)
        _RecordCard(
          icon: LucideIcons.repeat2,
          title: row.conversionNumber,
          subtitle:
              '${data.suppliers[row.supplierId]?.name ?? '#${row.supplierId}'} · '
              '${_date(row.convertedAt)} · ${row.lineCount} ${'consignment.lines'.tr()}\n'
              '${'consignment.conversion_evidence'.tr()}: ${row.evidenceReference}',
          status: row.status,
          trailing: row.status == 'posted'
              ? IconButton(
                  onPressed: data.historicalManagementEnabled
                      ? () => onVoidConversion(row.id)
                      : null,
                  icon: const Icon(LucideIcons.ban),
                  tooltip: 'consignment.void_conversion'.tr(),
                )
              : null,
        ),
      if (data.ownershipConversions.isNotEmpty && data.receipts.isNotEmpty)
        const Divider(height: 28),
      for (final row in data.receipts)
        _RecordCard(
          icon: LucideIcons.packageOpen,
          title: row.receiptNumber,
          subtitle:
              '${data.suppliers[row.supplierId]?.name ?? '#${row.supplierId}'} · '
              '${_date(row.receivedAt)} · ${row.lineCount} ${'consignment.lines'.tr()}',
          status: row.status,
          trailing: Wrap(
            spacing: 6,
            children: [
              if (row.status == 'draft')
                FilledButton.tonal(
                  onPressed: data.operationsEnabled
                      ? () => onPost(row.id)
                      : null,
                  child: Text('consignment.post'.tr()),
                ),
              if (row.status == 'posted')
                IconButton(
                  onPressed: () => onVoid(row.id),
                  icon: const Icon(LucideIcons.ban),
                  tooltip: 'consignment.void_receipt'.tr(),
                ),
            ],
          ),
        ),
    ],
  );
}

class _CustodySection extends StatelessWidget {
  const _CustodySection({
    required this.data,
    required this.onCreate,
    required this.onPost,
    required this.onVoid,
  });

  final ConsignmentDashboardSnapshot data;
  final VoidCallback onCreate;
  final ValueChanged<int> onPost;
  final ValueChanged<int> onVoid;

  @override
  Widget build(BuildContext context) => _SectionScaffold(
    title: 'consignment.custody_movements'.tr(),
    actionLabel: 'consignment.new_custody_movement'.tr(),
    onAction: data.operationsEnabled ? onCreate : null,
    empty: data.custodyDocuments.isEmpty,
    children: [
      const ConsignmentHelpCard(messageKey: 'consignment.guide_custody_notice'),
      const SizedBox(height: 12),
      for (final row in data.custodyDocuments)
        _RecordCard(
          icon: switch (row.documentType) {
            'supplier_return' => LucideIcons.undo2,
            'loss' => LucideIcons.packageX,
            _ => LucideIcons.triangleAlert,
          },
          title:
              '${row.documentNumber} - '
              '${'consignment.custody_type_${row.documentType}'.tr()}',
          subtitle:
              '${data.suppliers[row.supplierId]?.name ?? '#${row.supplierId}'} - '
              '${_date(row.occurredAt)} - '
              '${row.lineCount} ${'consignment.lines'.tr()}\n'
              '${'consignment.custody_responsibility'.tr()}: '
              '${'consignment.responsibility_${row.responsibility}'.tr()} - '
              '${row.reason}',
          status: row.status,
          trailing: Wrap(
            spacing: 6,
            children: [
              if (row.status == 'draft')
                FilledButton.tonal(
                  onPressed: data.operationsEnabled
                      ? () => onPost(row.id)
                      : null,
                  child: Text('consignment.post'.tr()),
                ),
              if (row.status == 'posted')
                IconButton(
                  onPressed: data.historicalManagementEnabled
                      ? () => onVoid(row.id)
                      : null,
                  icon: const Icon(LucideIcons.ban),
                  tooltip: 'consignment.void_custody'.tr(),
                ),
            ],
          ),
        ),
    ],
  );
}

class _SettlementsSection extends StatelessWidget {
  const _SettlementsSection({
    required this.data,
    required this.onCreate,
    required this.onReview,
    required this.onPost,
    required this.onPay,
    required this.onPayments,
    required this.onVoid,
  });
  final ConsignmentDashboardSnapshot data;
  final VoidCallback onCreate;
  final ValueChanged<int> onReview;
  final ValueChanged<int> onPost;
  final ValueChanged<ConsignmentSettlementStatement> onPay;
  final ValueChanged<ConsignmentSettlementStatement> onPayments;
  final ValueChanged<ConsignmentSettlementStatement> onVoid;

  @override
  Widget build(BuildContext context) => _SectionScaffold(
    title: 'consignment.settlements'.tr(),
    actionLabel: 'consignment.new_settlement'.tr(),
    onAction: data.historicalManagementEnabled ? onCreate : null,
    empty: data.statements.isEmpty,
    children: [
      for (final row in data.statements)
        _RecordCard(
          icon: LucideIcons.receiptText,
          title: row.statementNumber,
          subtitle:
              '${data.suppliers[row.supplierId]?.name ?? '#${row.supplierId}'} · '
              '${_date(row.periodStart)} – ${_date(row.periodEnd)}\n'
              '${'consignment.total'.tr()}: ${sl<CurrencyService>().formatForCode(row.totalCents, data.currencyCodes[row.currencyId] ?? sl<CurrencyService>().currencyCode)} · '
              '${'consignment.outstanding'.tr()}: ${sl<CurrencyService>().formatForCode(row.totalCents - row.paidCents, data.currencyCodes[row.currencyId] ?? sl<CurrencyService>().currencyCode)}',
          status: row.status,
          trailing: Wrap(
            spacing: 6,
            children: [
              if (row.status == 'draft')
                IconButton.filledTonal(
                  onPressed: data.historicalManagementEnabled
                      ? () => onReview(row.id)
                      : null,
                  icon: const Icon(LucideIcons.clipboardCheck),
                  tooltip: 'consignment.review'.tr(),
                ),
              if (row.status == 'reviewed')
                IconButton.filledTonal(
                  onPressed: data.operationsEnabled
                      ? () => onPost(row.id)
                      : null,
                  icon: const Icon(LucideIcons.send),
                  tooltip: 'consignment.post'.tr(),
                ),
              if ((row.status == 'posted' || row.status == 'partially_paid') &&
                  row.totalCents > row.paidCents)
                IconButton.filledTonal(
                  onPressed: () => onPay(row),
                  icon: const Icon(LucideIcons.walletCards),
                  tooltip: 'consignment.pay'.tr(),
                ),
              if (data.payments.any((payment) => payment.statementId == row.id))
                IconButton(
                  onPressed: () => onPayments(row),
                  icon: const Icon(LucideIcons.history),
                  tooltip: 'consignment.payments'.tr(),
                ),
              if (row.status != 'voided' &&
                  !data.payments.any(
                    (payment) =>
                        payment.statementId == row.id &&
                        payment.status == 'posted',
                  ))
                IconButton(
                  onPressed: () => onVoid(row),
                  icon: const Icon(LucideIcons.ban),
                  tooltip: 'consignment.void_statement'.tr(),
                ),
            ],
          ),
        ),
    ],
  );
}

class _ConsignmentReport extends StatefulWidget {
  const _ConsignmentReport({required this.data});
  final ConsignmentDashboardSnapshot data;

  @override
  State<_ConsignmentReport> createState() => _ConsignmentReportState();
}

class _ConsignmentReportState extends State<_ConsignmentReport> {
  late DateTime _start;
  late DateTime _end;
  int? _supplierId;
  late Future<List<ConsignmentSupplierReportRow>> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month);
    _end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _ConsignmentReport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) {
      _future = _load();
    }
  }

  Future<List<ConsignmentSupplierReportRow>> _load() =>
      sl<ConsignmentReportingService>().loadReport(
        range: ConsignmentReportRange(start: _start, end: _end),
        supplierId: _supplierId,
      );

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  ConsignmentReportRange get _range =>
      ConsignmentReportRange(start: _start, end: _end);

  Future<void> _export(int choice) async {
    try {
      final rows = await _future;
      if (!mounted) return;
      final supplierLabel = _supplierId == null
          ? 'consignment.all_suppliers'.tr()
          : widget.data.suppliers[_supplierId]?.name ?? '#$_supplierId';
      await ConsignmentReportExportService.export(
        context,
        rows: rows,
        range: _range,
        supplierLabel: supplierLabel,
        excel: choice == 2,
        share: choice == 1,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('consignment.export_failed'.tr())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = widget.data.suppliers.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'consignment.report_title'.tr(),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => context.push('/reports/sales/by-supplier'),
                  icon: const Icon(LucideIcons.externalLink),
                  label: Text('consignment.sales_detail'.tr()),
                ),
                PopupMenuButton<int>(
                  tooltip: 'consignment.export'.tr(),
                  onSelected: _export,
                  itemBuilder: (_) => [
                    for (final item in [
                      (0, 'print'),
                      (1, 'share'),
                      (2, 'excel'),
                    ])
                      PopupMenuItem(
                        value: item.$1,
                        child: Text('consignment.${item.$2}'.tr()),
                      ),
                  ],
                  icon: const Icon(LucideIcons.share2),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'consignment.report_note'.tr(),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final fieldWidth = constraints.maxWidth < 700
                ? constraints.maxWidth
                : 280.0;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: fieldWidth,
                  child: DropdownMenu<int>(
                    initialSelection: _supplierId ?? 0,
                    enableFilter: true,
                    enableSearch: true,
                    expandedInsets: EdgeInsets.zero,
                    label: Text('supplier_sales.search_supplier'.tr()),
                    dropdownMenuEntries: [
                      DropdownMenuEntry(
                        value: 0,
                        label: 'consignment.all_suppliers'.tr(),
                      ),
                      for (final supplier in suppliers)
                        DropdownMenuEntry(
                          value: supplier.id,
                          label: supplier.name,
                        ),
                    ],
                    onSelected: (value) => _supplierId =
                        value == null || value == 0 ? null : value,
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: _DateTile(
                    label: 'consignment.period_start'.tr(),
                    value: _start,
                    onChanged: (value) => setState(() {
                      _start = DateTime(value.year, value.month, value.day);
                    }),
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: _DateTile(
                    label: 'consignment.period_end'.tr(),
                    value: _end,
                    onChanged: (value) => setState(() {
                      _end = DateTime(
                        value.year,
                        value.month,
                        value.day,
                        23,
                        59,
                        59,
                        999,
                      );
                    }),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _end.isBefore(_start) ? null : _reload,
                  icon: const Icon(LucideIcons.listFilter),
                  label: Text('consignment.apply_filters'.tr()),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'consignment.period_balance_note'.tr(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<ConsignmentSupplierReportRow>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snapshot.hasError) {
              return _AccessOrError(error: snapshot.error, retry: _reload);
            }
            final rows = snapshot.data ?? const [];
            if (rows.isEmpty) return const _EmptyState();
            return Column(children: [for (final row in rows) _reportCard(row)]);
          },
        ),
      ],
    );
  }

  Widget _reportCard(ConsignmentSupplierReportRow row) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${row.supplierName} · ${row.currencyCode}',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 20,
            runSpacing: 14,
            children: [
              _ReportValue(
                'consignment.received_qty'.tr(),
                localizedQuantityTotals(row.receivedQuantities),
              ),
              _ReportValue(
                'consignment.converted_qty'.tr(),
                localizedQuantityTotals(row.convertedQuantities),
              ),
              _ReportValue(
                'consignment.gross_sold_qty'.tr(),
                localizedQuantityTotals(row.grossSoldQuantities),
              ),
              _ReportValue(
                'consignment.returned_qty'.tr(),
                localizedQuantityTotals(row.returnedQuantities),
              ),
              _ReportValue(
                'consignment.supplier_returned_qty'.tr(),
                localizedQuantityTotals(row.supplierReturnQuantities),
              ),
              _ReportValue(
                'consignment.custody_loss_qty'.tr(),
                localizedQuantityTotals(row.lossQuantities),
              ),
              _ReportValue(
                'consignment.custody_damage_qty'.tr(),
                localizedQuantityTotals(row.damageQuantities),
              ),
              _ReportValue(
                'consignment.net_sold_qty'.tr(),
                localizedQuantityTotals(row.netSoldQuantities),
              ),
              _ReportValue(
                'consignment.remaining_qty'.tr(),
                localizedQuantityTotals(row.remainingQuantities),
              ),
              _ReportValue(
                'consignment.unavailable_qty'.tr(),
                localizedQuantityTotals(row.unavailableQuantities),
              ),
              _ReportValue(
                'consignment.period_obligation'.tr(),
                _rowMoney(row.periodObligationCents, row.currencyCode),
              ),
              _ReportValue(
                'consignment.settled_in_period'.tr(),
                _rowMoney(row.postedSettlementCents, row.currencyCode),
              ),
              _ReportValue(
                'consignment.paid_in_period'.tr(),
                _rowMoney(row.paidCents, row.currencyCode),
              ),
              _ReportValue(
                'consignment.closing_unsettled'.tr(),
                _rowMoney(row.unsettledObligationCents, row.currencyCode),
              ),
              _ReportValue(
                'consignment.closing_payable'.tr(),
                _rowMoney(row.outstandingPayableCents, row.currencyCode),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  String _rowMoney(int amount, String code) =>
      sl<CurrencyService>().formatForCode(amount, code);
}

class _AgreementSheet extends StatefulWidget {
  const _AgreementSheet({this.existing});
  final ConsignmentAgreement? existing;
  @override
  State<_AgreementSheet> createState() => _AgreementSheetState();
}

class _AgreementSheetState extends State<_AgreementSheet> {
  final _formKey = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _value = TextEditingController();
  final _paymentDays = TextEditingController(text: '0');
  final _tax = TextEditingController(text: '0');
  final _notes = TextEditingController();
  int? _supplierId;
  int? _choiceIndex;
  String _basis = 'fixed_unit_cost';
  String _frequency = 'monthly';
  bool _taxInclusive = false;
  bool _activate = true;
  bool _allSupplierReceiptsConsignment = false;
  bool _loading = true;
  bool _importing = false;
  bool _showAllProducts = false;
  final Map<int, int> _recordedUnitCosts = {};
  final Map<int, Set<int>> _supplierVariants = {};

  bool _visibleChoice(_VariantChoice choice) =>
      _supplierId != null &&
      (_showAllProducts ||
          (_supplierVariants[_supplierId]?.contains(choice.variantId) ??
              false));
  DateTime _effectiveFrom = DateTime.now();
  List<Supplier> _suppliers = [];
  Map<int, String> _currencyCodes = {};
  List<_VariantChoice> _choices = [];
  final List<ConsignmentAgreementTermInput> _terms = [];
  final List<_AgreementTermChoice> _termChoices = [];
  final List<String> _termLabels = [];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) {
      _number.text =
          'CON-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    } else {
      _number.text = existing.agreementNumber;
      _supplierId = existing.supplierId;
      _frequency = existing.settlementFrequency;
      _paymentDays.text = existing.paymentTermsDays.toString();
      _tax.text = _basisPointsToPercent(existing.settlementTaxRateBps);
      _taxInclusive = existing.settlementTaxInclusive;
      _notes.text = existing.notes;
      _effectiveFrom = DateTime.now();
    }
    _load();
  }

  Future<void> _load() async {
    final db = sl<AppDatabase>();
    final suppliers =
        await (db.select(db.suppliers)
              ..where((row) => row.isActive.equals(true))
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    final links = await db.customSelect(
      '''SELECT pu.supplier_id, v.id AS variant_id
      FROM purchases pu JOIN purchase_items pi ON pi.purchase_id=pu.id
      JOIN product_variants v ON v.product_id=pi.product_id
        AND (pi.variant_id=v.id OR (pi.variant_id IS NULL AND
          (SELECT COUNT(*) FROM product_variants x WHERE x.product_id=pi.product_id)=1))
      WHERE pu.status='posted'
      UNION SELECT supplier_id,canonical_variant_id FROM supplier_product_identities
      UNION SELECT a.supplier_id,v.id FROM consignment_agreements a
      JOIN consignment_agreement_items i ON i.agreement_id=a.id
      JOIN product_variants v ON v.product_id=i.product_id
        AND (i.variant_id IS NULL OR i.variant_id=v.id)''',
    ).get();
    for (final row in links) {
      _supplierVariants
          .putIfAbsent(row.read<int>('supplier_id'), () => <int>{})
          .add(row.read<int>('variant_id'));
    }
    final currencies = await db.select(db.currencies).get();
    final rows = await db.customSelect(
      '''SELECT v.id AS variant_id,p.id AS product_id,
      COALESCE(v.cost_cents,p.cost_cents,0) AS recorded_cost_cents,
      p.name AS product_name,COALESCE(v.sku,p.sku,'') AS sku,
      COALESCE(v.barcode,p.barcode,'') AS barcode,p.currency_id,
      p.inventory_tracking_type,p.costing_method,p.measurement_type
      FROM product_variants v JOIN products p ON p.id=v.product_id
      WHERE p.is_active=1 AND v.is_active=1 AND p.track_inventory=1
      ORDER BY p.name,v.id''',
    ).get();
    final agreementItems = widget.existing == null
        ? <ConsignmentAgreementItem>[]
        : await (db.select(
            db.consignmentAgreementItems,
          )..where((row) => row.agreementId.equals(widget.existing!.id))).get();
    if (!mounted) return;
    setState(() {
      _suppliers = suppliers;
      final selectedSupplier = _supplierId == null
          ? null
          : suppliers.cast<Supplier?>().firstWhere(
              (row) => row!.id == _supplierId,
              orElse: () => null,
            );
      _allSupplierReceiptsConsignment =
          selectedSupplier?.defaultSupplyMode == 'consignment';
      _currencyCodes = {for (final row in currencies) row.id: row.code};
      for (final row in rows) {
        _recordedUnitCosts[row.read<int>('variant_id')] = row.read<int>(
          'recorded_cost_cents',
        );
      }
      _choices = rows
          .map(
            (row) => _VariantChoice(
              variantId: row.read<int>('variant_id'),
              productId: row.read<int>('product_id'),
              currencyId: row.read<int>('currency_id'),
              label: _variantSearchLabel(
                productName: row.read<String>('product_name'),
                sku: row.read<String>('sku'),
                barcode: row.read<String>('barcode'),
                variantId: row.read<int>('variant_id'),
              ),
              trackingType: row.read<String>('inventory_tracking_type'),
              costingMethod: row.read<String>('costing_method'),
              measurementType: row.read<String>('measurement_type'),
            ),
          )
          .toList();
      for (final item in agreementItems) {
        final choice = _choices.cast<_VariantChoice?>().firstWhere(
          (row) =>
              row!.productId == item.productId &&
              row.variantId == item.variantId,
          orElse: () => null,
        );
        final currencyId = choice?.currencyId ?? widget.existing!.currencyId;
        _termChoices.add(
          _AgreementTermChoice(
            productId: item.productId,
            variantId: item.variantId,
            currencyId: currencyId,
          ),
        );
        _termLabels.add(
          choice?.label ??
              '#${item.productId} · ${'consignment.all_variants'.tr()}',
        );
        _terms.add(
          item.settlementBasis == 'fixed_unit_cost'
              ? ConsignmentAgreementTermInput.fixedCost(
                  productId: item.productId,
                  variantId: item.variantId,
                  amountCents: item.unitCostCents!,
                )
              : ConsignmentAgreementTermInput.salesPercentage(
                  productId: item.productId,
                  variantId: item.variantId,
                  shareBps: item.supplierShareBps!,
                  includeLineDiscount: item.includeLineDiscount,
                  includeInvoiceDiscount: item.includeInvoiceDiscount,
                  includeSalesTax: item.includeSalesTax,
                ),
        );
      }
      _loading = false;
    });
  }

  void _prefillRecordedCost() {
    if (_basis != 'fixed_unit_cost' || _choiceIndex == null) return;
    _value.clear();
    final choice = _choices[_choiceIndex!];
    final cents = _recordedUnitCosts[choice.variantId];
    if (cents == null) return;
    final code =
        _currencyCodes[choice.currencyId] ?? sl<CurrencyService>().currencyCode;
    final digits = sl<CurrencyService>().decimalDigitsForCode(code);
    final raw = cents.abs().toString().padLeft(digits + 1, '0');
    _value.text =
        '${cents < 0 ? '-' : ''}${digits == 0 ? raw : '${raw.substring(0, raw.length - digits)}.${raw.substring(raw.length - digits)}'}';
  }

  int? _percentageBps() {
    final percent = num.tryParse(_value.text.trim().replaceAll(',', '.'));
    if (percent == null || percent < 0 || percent > 100) return null;
    return (percent * 100).round();
  }

  void _addTerm() {
    if (_choiceIndex == null || _value.text.trim().isEmpty) {
      _showNotice('consignment.term_required'.tr());
      return;
    }
    if (_terms.length >= 500) {
      _showNotice('consignment.limit_reached'.tr());
      return;
    }
    final choice = _choices[_choiceIndex!];
    if (_termChoices.any(
      (row) =>
          row.productId == choice.productId &&
          row.variantId == choice.variantId,
    )) {
      return;
    }
    if (_basis == 'fixed_unit_cost') {
      final currencyCode =
          _currencyCodes[choice.currencyId] ??
          sl<CurrencyService>().currencyCode;
      final parsed = sl<MoneyInputParser>().parse(
        _value.text,
        decimalDigits: sl<CurrencyService>().decimalDigitsForCode(currencyCode),
      );
      if (!parsed.isValid) return;
      _terms.add(
        ConsignmentAgreementTermInput.fixedCost(
          productId: choice.productId,
          variantId: choice.variantId,
          amountCents: parsed.cents,
        ),
      );
    } else {
      final shareBps = _percentageBps();
      if (shareBps == null) return;
      _terms.add(
        ConsignmentAgreementTermInput.salesPercentage(
          productId: choice.productId,
          variantId: choice.variantId,
          shareBps: shareBps,
        ),
      );
    }
    setState(() {
      _termChoices.add(
        _AgreementTermChoice(
          productId: choice.productId,
          variantId: choice.variantId,
          currencyId: choice.currencyId,
        ),
      );
      _termLabels.add(choice.label);
      _choiceIndex = null;
      if (_basis == 'fixed_unit_cost') _value.clear();
    });
  }

  Future<void> _importOnePurchase() async {
    final supplierId = _supplierId;
    if (supplierId == null) {
      _showNotice('consignment.select_supplier_first'.tr());
      return;
    }
    final supplier = _suppliers.firstWhere((row) => row.id == supplierId);
    final service = ConsignmentAgreementImportService(sl<AppDatabase>());
    final invoices = await service.listPostedPurchases(
      supplierId: supplierId,
      currencyId: supplier.currencyId,
    );
    if (!mounted) return;
    if (invoices.isEmpty) {
      _showNotice('consignment.no_posted_purchases'.tr());
      return;
    }
    final purchaseId = await showDialog<int>(
      context: context,
      builder: (context) => _PurchaseInvoicePickerDialog(invoices: invoices),
    );
    if (purchaseId != null) await _importPurchases(purchaseId: purchaseId);
  }

  Future<void> _importAllPurchases() async {
    if (_supplierId == null) {
      _showNotice('consignment.select_supplier_first'.tr());
      return;
    }
    await _importPurchases();
  }

  Future<void> _importPurchases({int? purchaseId}) async {
    if (_importing) return;
    final supplierId = _supplierId;
    if (supplierId == null) return;
    final supplier = _suppliers.firstWhere((row) => row.id == supplierId);
    final percentageBps = _basis == 'net_sales_percentage'
        ? _percentageBps()
        : null;
    if (_basis == 'net_sales_percentage' && percentageBps == null) {
      _showNotice('consignment.percentage_required'.tr());
      return;
    }
    setState(() => _importing = true);
    try {
      final result = await ConsignmentAgreementImportService(sl<AppDatabase>())
          .buildTerms(
            supplierId: supplierId,
            currencyId: supplier.currencyId,
            purchaseId: purchaseId,
          );
      if (!mounted) return;
      var added = 0;
      var retained = 0;
      var skipped = result.skippedLines;
      final additions = <(_VariantChoice, ConsignmentPurchaseImportItem)>[];
      for (final imported in result.items) {
        final choiceIndex = _choices.indexWhere(
          (choice) =>
              choice.productId == imported.productId &&
              choice.variantId == imported.variantId,
        );
        if (choiceIndex < 0) {
          skipped++;
          continue;
        }
        final choice = _choices[choiceIndex];
        if (_termChoices.any(
          (row) =>
              row.productId == choice.productId &&
              row.variantId == choice.variantId,
        )) {
          retained++;
          continue;
        }
        if (_terms.length + additions.length >= 500) {
          skipped++;
          continue;
        }
        additions.add((choice, imported));
      }
      setState(() {
        for (final entry in additions) {
          final choice = entry.$1;
          final imported = entry.$2;
          _termChoices.add(
            _AgreementTermChoice(
              productId: choice.productId,
              variantId: choice.variantId,
              currencyId: choice.currencyId,
            ),
          );
          _termLabels.add(choice.label);
          _terms.add(
            ConsignmentAgreementImportService.toAgreementTerm(
              imported,
              settlementBasis: _basis,
              supplierShareBps: percentageBps,
            ),
          );
          added++;
        }
      });
      _showNotice(
        (_basis == 'fixed_unit_cost'
                ? 'consignment.import_result'
                : 'consignment.import_result_percentage')
            .tr(
              namedArgs: {
                'added': '$added',
                'retained': '$retained',
                'varied': '${result.variedCostItems}',
                'skipped': '$skipped',
              },
            ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _settlementMethodCard(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    color: Theme.of(
      context,
    ).colorScheme.secondaryContainer.withValues(alpha: .45),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'consignment.settlement_method_title'.tr(),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'consignment.settlement_method_help'.tr(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'fixed_unit_cost',
                label: Text('consignment.fixed_cost'.tr()),
              ),
              ButtonSegment(
                value: 'net_sales_percentage',
                label: Text('consignment.sales_share'.tr()),
              ),
            ],
            selected: {_basis},
            onSelectionChanged: (value) => setState(() {
              _basis = value.single;
              _value.clear();
              _prefillRecordedCost();
            }),
          ),
          const SizedBox(height: 10),
          Text(
            (_basis == 'fixed_unit_cost'
                    ? 'consignment.fixed_import_help'
                    : 'consignment.percentage_help')
                .tr(),
          ),
          if (_basis == 'net_sales_percentage') ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('consignment-bulk-percentage'),
              controller: _value,
              onTap: () => _selectAll(_value),
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'consignment.share_percent'.tr(),
                suffixText: '%',
              ),
            ),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => _SheetFrame(
    title:
        (widget.existing == null
                ? 'consignment.new_agreement'
                : 'consignment.revise_agreement')
            .tr(),
    child: _loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: Column(
              children: [
                const ConsignmentHelpCard(
                  messageKey: 'consignment.guide_agreement_notice',
                ),
                const SizedBox(height: 16),
                DropdownMenu<int>(
                  initialSelection: _supplierId,
                  enabled: widget.existing == null,
                  enableFilter: true,
                  enableSearch: true,
                  requestFocusOnTap: true,
                  menuHeight: 420,
                  expandedInsets: EdgeInsets.zero,
                  leadingIcon: const Icon(LucideIcons.search),
                  label: Text('consignment.search_supplier'.tr()),
                  dropdownMenuEntries: [
                    for (final row in _suppliers)
                      DropdownMenuEntry(
                        value: row.id,
                        label: _supplierSearchLabel(row),
                      ),
                  ],
                  onSelected: widget.existing == null
                      ? (value) => setState(() {
                          if (_supplierId != value) {
                            _terms.clear();
                            _termChoices.clear();
                            _termLabels.clear();
                            _choiceIndex = null;
                            _value.clear();
                            _showAllProducts = false;
                          }
                          _supplierId = value;
                          _allSupplierReceiptsConsignment =
                              value != null &&
                              _suppliers
                                      .firstWhere((row) => row.id == value)
                                      .defaultSupplyMode ==
                                  'consignment';
                        })
                      : null,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'consignment.agreement_items_help'.tr(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _settlementMethodCard(context),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'consignment.import_purchase_title'.tr(),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'consignment.import_purchase_help'.tr(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _supplierId == null || _importing
                                  ? null
                                  : _importOnePurchase,
                              icon: const Icon(LucideIcons.fileSearch),
                              label: Text(
                                'consignment.import_one_purchase'.tr(),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _supplierId == null || _importing
                                  ? null
                                  : _importAllPurchases,
                              icon: const Icon(LucideIcons.files),
                              label: Text(
                                'consignment.import_all_purchases'.tr(),
                              ),
                            ),
                            if (_importing)
                              const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('consignment.supplier_default_consignment'.tr()),
                  subtitle: Text(
                    'consignment.supplier_default_consignment_help'.tr(),
                  ),
                  value: _allSupplierReceiptsConsignment,
                  onChanged: (value) =>
                      setState(() => _allSupplierReceiptsConsignment = value),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _number,
                  onTap: () => _selectAll(_number),
                  decoration: InputDecoration(
                    labelText: 'consignment.agreement_number'.tr(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                _DateTile(
                  label: 'consignment.effective_from'.tr(),
                  value: _effectiveFrom,
                  onChanged: (value) => setState(() => _effectiveFrom = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _frequency,
                  decoration: InputDecoration(
                    labelText: 'consignment.frequency'.tr(),
                  ),
                  items: [
                    for (final value in [
                      'immediate',
                      'daily',
                      'weekly',
                      'monthly',
                      'manual',
                    ])
                      DropdownMenuItem(
                        value: value,
                        child: Text('consignment.frequency_$value'.tr()),
                      ),
                  ],
                  onChanged: (value) => setState(() => _frequency = value!),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _paymentDays,
                        onTap: () => _selectAll(_paymentDays),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: 'consignment.payment_days'.tr(),
                        ),
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _tax,
                        onTap: () => _selectAll(_tax),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'consignment.tax_percent'.tr(),
                        ),
                        validator: _required,
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('consignment.tax_inclusive'.tr()),
                  value: _taxInclusive,
                  onChanged: (value) => setState(() => _taxInclusive = value),
                ),
                const Divider(height: 28),
                Text('consignment.terms_help'.tr()),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('consignment.show_all_products'.tr()),
                  subtitle: Text('consignment.show_all_products_help'.tr()),
                  value: _showAllProducts,
                  onChanged: _supplierId == null
                      ? null
                      : (value) => setState(() {
                          _showAllProducts = value;
                          _choiceIndex = null;
                          if (_basis == 'fixed_unit_cost') _value.clear();
                        }),
                ),
                DropdownMenu<int>(
                  key: ValueKey(
                    'agreement-product-$_supplierId-$_showAllProducts-${_terms.length}-$_choiceIndex',
                  ),
                  initialSelection: _choiceIndex,
                  enableFilter: true,
                  enableSearch: true,
                  requestFocusOnTap: true,
                  menuHeight: 420,
                  expandedInsets: EdgeInsets.zero,
                  leadingIcon: const Icon(LucideIcons.search),
                  label: Text('consignment.search_product'.tr()),
                  dropdownMenuEntries: [
                    for (var index = 0; index < _choices.length; index++)
                      if (_visibleChoice(_choices[index]))
                        DropdownMenuEntry(
                          value: index,
                          label: _choices[index].label,
                        ),
                  ],
                  onSelected: (value) => setState(() {
                    _choiceIndex = value;
                    _prefillRecordedCost();
                  }),
                ),
                if (_basis == 'fixed_unit_cost' && _choiceIndex != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'consignment.recorded_cost_help'.tr(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 12),
                if (_basis == 'fixed_unit_cost')
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _value,
                          onTap: () => _selectAll(_value),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'consignment.unit_cost'.tr(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: _choiceIndex == null ? null : _addTerm,
                        icon: const Icon(LucideIcons.plus),
                        label: Text('consignment.add_term'.tr()),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'consignment.percentage_applies_to_added'.tr(
                            namedArgs: {'percent': _value.text.trim()},
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: _choiceIndex == null ? null : _addTerm,
                        icon: const Icon(LucideIcons.plus),
                        label: Text('consignment.add_term'.tr()),
                      ),
                    ],
                  ),
                if (_termLabels.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'consignment.agreement_items_count'.tr(
                        namedArgs: {'count': '${_termLabels.length}'},
                      ),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var index = 0; index < _termLabels.length; index++)
                          InputChip(
                            label: Text(_agreementTermLabel(index)),
                            onDeleted: () => setState(() {
                              _termLabels.removeAt(index);
                              _termChoices.removeAt(index);
                              _terms.removeAt(index);
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: 'common.notes'.tr()),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('consignment.activate_now'.tr()),
                  value: _activate,
                  onChanged: (value) => setState(() => _activate = value),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(LucideIcons.check),
                    label: Text('common.save'.tr()),
                  ),
                ),
              ],
            ),
          ),
  );

  @override
  void dispose() {
    _number.dispose();
    _value.dispose();
    _paymentDays.dispose();
    _tax.dispose();
    _notes.dispose();
    super.dispose();
  }

  String _agreementTermLabel(int index) {
    final term = _terms[index];
    final value = term.settlementBasis == 'fixed_unit_cost'
        ? sl<CurrencyService>().formatForCode(
            term.unitCostCents!,
            _currencyCodes[_termChoices[index].currencyId] ??
                sl<CurrencyService>().currencyCode,
          )
        : '${_basisPointsToPercent(term.supplierShareBps!)}%';
    return '${_termLabels[index]} · $value';
  }

  void _submit() {
    if (!_formKey.currentState!.validate() ||
        _supplierId == null ||
        _terms.isEmpty) {
      return;
    }
    final supplier = _suppliers.firstWhere((row) => row.id == _supplierId);
    if (_termChoices.any(
      (choice) => choice.currencyId != supplier.currencyId,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('consignment.currency_mismatch'.tr())),
      );
      return;
    }
    final tax = num.tryParse(_tax.text.replaceAll(',', '.'));
    if (tax == null || tax < 0 || tax > 100) return;
    Navigator.pop(
      context,
      _AgreementInput(
        supplierId: supplier.id,
        currencyId: supplier.currencyId,
        number: _number.text.trim(),
        effectiveFrom: _effectiveFrom,
        frequency: _frequency,
        paymentTermsDays: int.tryParse(_paymentDays.text) ?? 0,
        taxRateBps: (tax * 100).round(),
        taxInclusive: _taxInclusive,
        notes: _notes.text.trim(),
        terms: List.unmodifiable(_terms),
        supplierMode: _allSupplierReceiptsConsignment ? 'consignment' : 'mixed',
        activate: _activate,
      ),
    );
  }
}

class _ConversionSheet extends StatefulWidget {
  const _ConversionSheet({required this.data});

  final ConsignmentDashboardSnapshot data;

  @override
  State<_ConversionSheet> createState() => _ConversionSheetState();
}

class _ConversionSheetState extends State<_ConversionSheet> {
  final _number = TextEditingController();
  final _evidence = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _notes = TextEditingController();
  String? _agreementId;
  String? _sourceKey;
  bool _loading = false;
  List<_ConversionSourceChoice> _sources = [];
  final List<ConsignmentOwnershipConversionLineInput> _lines = [];
  final List<_ConversionSourceChoice> _lineSources = [];

  @override
  void initState() {
    super.initState();
    _number.text = 'CO-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}';
  }

  Future<void> _selectAgreement(String? agreementId) async {
    setState(() {
      _agreementId = agreementId;
      _sourceKey = null;
      _sources = [];
      _lines.clear();
      _lineSources.clear();
      _loading = agreementId != null;
    });
    if (agreementId == null) return;
    final agreement = widget.data.agreements.firstWhere(
      (row) => row.id == agreementId,
    );
    final db = sl<AppDatabase>();
    final localScope = await LocalBranchScope.read(db);
    final operationScope = await WarehouseOperationScope.resolve(
      db,
      warehouseId: localScope.warehouseId,
    );
    final variants = await db
        .customSelect(
          '''SELECT DISTINCT p.id AS product_id,p.name AS product_name,
                v.id AS variant_id,COALESCE(v.sku,p.sku,'') AS sku,
                COALESCE(v.barcode,p.barcode,'') AS barcode
             FROM consignment_agreement_items ai
             JOIN products p ON p.id=ai.product_id
             JOIN product_variants v ON v.product_id=p.id AND v.is_active=1
             WHERE ai.agreement_id=?
               AND (ai.variant_id IS NULL OR ai.variant_id=v.id)
               AND p.is_active=1 AND p.track_inventory=1
             ORDER BY p.name,v.id''',
          variables: [Variable.withString(agreementId)],
          readsFrom: {
            db.consignmentAgreementItems,
            db.products,
            db.productVariants,
          },
        )
        .get();
    final reader = InventoryStockSourceService(db);
    final choices = <_ConversionSourceChoice>[];
    for (final row in variants) {
      final productId = row.read<int>('product_id');
      final variantId = row.read<int>('variant_id');
      final snapshot = await reader.loadProduct(
        productId,
        variantId: variantId,
        scope: operationScope,
      );
      final warehouseStock =
          await (db.select(db.businessWarehouseStocks)..where(
                (stock) =>
                    stock.warehouseId.equals(operationScope.warehouseId) &
                    stock.variantId.equals(variantId),
              ))
              .getSingleOrNull();
      final productLabel = _variantSearchLabel(
        productName: row.read<String>('product_name'),
        sku: row.read<String>('sku'),
        barcode: row.read<String>('barcode'),
        variantId: variantId,
      );
      for (final source in snapshot.sources) {
        if (source.ownership != InventoryStockOwnership.enterprise ||
            source.supplierId != agreement.supplierId ||
            source.quantity <= 0 ||
            (source.supplierIdentityId == null && source.batchId == null)) {
          continue;
        }
        final sourceRef = source.sourceCode?.trim().isNotEmpty == true
            ? source.sourceCode!
            : source.batchNumber ?? '#${source.batchId}';
        final unitCostCents = source.batchId == null
            ? warehouseStock?.unitCostCents ?? 0
            : (await (db.select(db.productBatches)
                        ..where((batch) => batch.id.equals(source.batchId!)))
                      .getSingle())
                  .unitCostCents
                  .toBigInt()
                  .toInt();
        choices.add(
          _ConversionSourceChoice(
            key:
                '$variantId:${source.supplierIdentityId ?? 0}:${source.batchId ?? 0}',
            source: source,
            unitCostCents: unitCostCents,
            label:
                '$productLabel · $sourceRef · '
                '${'consignment.available'.tr()}: '
                '${MeasuredQuantity.majorValue(source.quantity, MeasurementType.fromDb(source.measurementType))}',
          ),
        );
      }
    }
    if (!mounted || _agreementId != agreementId) return;
    setState(() {
      _sources = choices;
      _loading = false;
      if (choices.length == 1) _sourceKey = choices.single.key;
    });
  }

  void _addLine() {
    final sourceKey = _sourceKey;
    if (sourceKey == null) {
      _showError('consignment.conversion_source_required'.tr());
      return;
    }
    final choice = _sources.firstWhere((row) => row.key == sourceKey);
    late final int quantity;
    try {
      quantity = MeasuredQuantity.parseToStored(
        _quantity.text,
        MeasurementType.fromDb(choice.source.measurementType).majorUnit,
      );
    } on FormatException {
      _showError('consignment.quantity_invalid'.tr());
      return;
    }
    if (quantity <= 0 || quantity > choice.source.quantity) {
      _showError('consignment.conversion_source_insufficient'.tr());
      return;
    }
    if (_lines.any((line) => line.variantId == choice.source.variantId)) {
      _showError('consignment.conversion_duplicate_variant'.tr());
      return;
    }
    setState(() {
      _lines.add(
        ConsignmentOwnershipConversionLineInput(
          productId: choice.source.productId,
          variantId: choice.source.variantId,
          quantity: quantity,
          supplierIdentityId: choice.source.batchId == null
              ? choice.source.supplierIdentityId
              : null,
          sourceBatchId: choice.source.batchId,
        ),
      );
      _lineSources.add(choice);
      _sourceKey = null;
      _quantity.text = '1';
    });
  }

  void _submit() {
    final agreementId = _agreementId;
    if (agreementId == null ||
        _lines.isEmpty ||
        _number.text.trim().isEmpty ||
        _evidence.text.trim().isEmpty) {
      _showError('common.required'.tr());
      return;
    }
    Navigator.pop(
      context,
      _ConversionInput(
        agreementId: agreementId,
        number: _number.text.trim(),
        evidenceReference: _evidence.text.trim(),
        convertedAt: DateTime.now(),
        notes: _notes.text.trim(),
        lines: List.unmodifiable(_lines),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _number.dispose();
    _evidence.dispose();
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agreements = widget.data.agreements
        .where((row) => row.status == 'active')
        .toList();
    final selected = _sourceKey == null
        ? null
        : _sources.firstWhere((row) => row.key == _sourceKey);
    return _SheetFrame(
      title: 'consignment.new_ownership_conversion'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ConsignmentHelpCard(
            messageKey: 'consignment.guide_conversion_notice',
          ),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'consignment.conversion_accounting_effect'.tr(),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownMenu<String>(
            initialSelection: _agreementId,
            enableFilter: true,
            enableSearch: true,
            requestFocusOnTap: true,
            expandedInsets: EdgeInsets.zero,
            menuHeight: 420,
            leadingIcon: const Icon(LucideIcons.search),
            label: Text('consignment.search_agreement'.tr()),
            dropdownMenuEntries: [
              for (final row in agreements)
                DropdownMenuEntry(
                  value: row.id,
                  label:
                      '${row.agreementNumber} - '
                      '${widget.data.suppliers[row.supplierId]?.name ?? ''}',
                ),
            ],
            onSelected: _selectAgreement,
          ),
          const SizedBox(height: 12),
          if (_loading)
            const LinearProgressIndicator()
          else if (_agreementId != null && _sources.isEmpty)
            Text('consignment.no_convertible_stock'.tr())
          else if (_agreementId != null)
            DropdownMenu<String>(
              key: ValueKey('conversion-source-$_agreementId-$_sourceKey'),
              initialSelection: _sourceKey,
              enableFilter: true,
              enableSearch: true,
              requestFocusOnTap: true,
              expandedInsets: EdgeInsets.zero,
              menuHeight: 420,
              leadingIcon: const Icon(LucideIcons.search),
              label: Text('consignment.search_conversion_source'.tr()),
              dropdownMenuEntries: [
                for (final source in _sources)
                  DropdownMenuEntry(value: source.key, label: source.label),
              ],
              onSelected: (value) => setState(() => _sourceKey = value),
            ),
          if (selected != null) ...[
            const SizedBox(height: 10),
            Text(
              'consignment.conversion_selected_source_help'.tr(
                namedArgs: {
                  'supplier': selected.source.supplierName ?? '',
                  'code':
                      selected.source.sourceCode ??
                      selected.source.batchNumber ??
                      '#${selected.source.batchId}',
                },
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              'consignment.conversion_recorded_cost'.tr(
                namedArgs: {
                  'amount': sl<CurrencyService>().formatForCode(
                    selected.unitCostCents,
                    widget.data.currencyCodes[widget.data.agreements
                            .firstWhere((row) => row.id == _agreementId)
                            .currencyId] ??
                        sl<CurrencyService>().currencyCode,
                  ),
                },
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _quantity,
              onTap: () => _selectAll(_quantity),
              keyboardType: TextInputType.numberWithOptions(
                decimal:
                    MeasurementType.fromDb(selected.source.measurementType) !=
                    MeasurementType.piece,
              ),
              decoration: InputDecoration(
                labelText: 'consignment.quantity'.tr(),
                helperText: 'consignment.conversion_quantity_help'.tr(),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonalIcon(
                onPressed: _addLine,
                icon: const Icon(LucideIcons.plus),
                label: Text('consignment.add_line'.tr()),
              ),
            ),
          ],
          if (_lines.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'consignment.conversion_lines_count'.tr(
                namedArgs: {'count': '${_lines.length}'},
              ),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (var index = 0; index < _lines.length; index++)
              Card(
                child: ListTile(
                  title: Text(_lineSources[index].label),
                  subtitle: Text(
                    '${"consignment.quantity".tr()}: '
                    '${MeasuredQuantity.majorValue(_lines[index].quantity, MeasurementType.fromDb(_lineSources[index].source.measurementType))} · '
                    '${"consignment.conversion_recorded_cost".tr(namedArgs: {"amount": sl<CurrencyService>().formatForCode(_lineSources[index].unitCostCents, widget.data.currencyCodes[widget.data.agreements.firstWhere((row) => row.id == _agreementId).currencyId] ?? sl<CurrencyService>().currencyCode)})}',
                  ),
                  trailing: IconButton(
                    tooltip: 'common.delete'.tr(),
                    icon: const Icon(LucideIcons.trash2),
                    onPressed: () => setState(() {
                      _lines.removeAt(index);
                      _lineSources.removeAt(index);
                    }),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _number,
            onTap: () => _selectAll(_number),
            decoration: InputDecoration(
              labelText: 'consignment.conversion_number'.tr(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _evidence,
            onTap: () => _selectAll(_evidence),
            maxLength: 200,
            decoration: InputDecoration(
              labelText: 'consignment.conversion_evidence'.tr(),
              helperText: 'consignment.conversion_evidence_help'.tr(),
            ),
          ),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: InputDecoration(labelText: 'common.notes'.tr()),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(LucideIcons.check),
            label: Text('consignment.confirm_conversion'.tr()),
          ),
        ],
      ),
    );
  }
}

class _ReceiptSheet extends StatefulWidget {
  const _ReceiptSheet({required this.data});
  final ConsignmentDashboardSnapshot data;
  @override
  State<_ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends State<_ReceiptSheet> {
  final _number = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _lot = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _expiry;
  String? _agreementId;
  int? _termIndex;
  bool _post = true;
  bool _loadingTerms = false;
  List<_VariantChoice> _choices = [];
  final List<ConsignmentReceiptLineInput> _lines = [];
  final List<int> _lineVariantIds = [];
  final List<String> _labels = [];

  @override
  void initState() {
    super.initState();
    _number.text =
        'CR-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
  }

  Future<void> _selectAgreement(String? id) async {
    setState(() {
      _agreementId = id;
      _termIndex = null;
      _loadingTerms = id != null;
      _choices = [];
      _lines.clear();
      _lineVariantIds.clear();
      _labels.clear();
    });
    if (id == null) return;
    final db = sl<AppDatabase>();
    final terms = await (db.select(
      db.consignmentAgreementItems,
    )..where((row) => row.agreementId.equals(id))).get();
    final choices = <_VariantChoice>[];
    for (final term in terms) {
      final variants =
          await (db.select(db.productVariants)..where(
                (row) =>
                    row.productId.equals(term.productId) &
                    row.isActive.equals(true) &
                    (term.variantId == null
                        ? const Constant(true)
                        : row.id.equals(term.variantId!)),
              ))
              .get();
      final product = await (db.select(
        db.products,
      )..where((row) => row.id.equals(term.productId))).getSingle();
      for (final variant in variants) {
        choices.add(
          _VariantChoice(
            variantId: variant.id,
            productId: product.id,
            currencyId: product.currencyId ?? 0,
            label: _variantSearchLabel(
              productName: product.name,
              sku: variant.sku ?? product.sku ?? '',
              barcode: variant.barcode ?? product.barcode ?? '',
              variantId: variant.id,
            ),
            trackingType: product.inventoryTrackingType,
            costingMethod: product.costingMethod,
            measurementType: product.measurementType,
          ),
        );
      }
    }
    if (!mounted || _agreementId != id) return;
    setState(() {
      _choices = choices;
      _loadingTerms = false;
    });
  }

  void _addLine() {
    if (_termIndex == null) return;
    final choice = _choices[_termIndex!];
    late final int quantity;
    try {
      quantity = MeasuredQuantity.parseToStored(
        _quantity.text,
        MeasurementType.fromDb(choice.measurementType).majorUnit,
      );
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('consignment.quantity_invalid'.tr())),
      );
      return;
    }
    if (quantity <= 0 || _lines.length >= 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('consignment.quantity_invalid'.tr())),
      );
      return;
    }
    if (_lines.any(
      (line) =>
          line.variantId == choice.variantId &&
          (line.manufacturerLotNumber ?? '') == _lot.text.trim() &&
          line.expiryDate == _expiry,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('consignment.duplicate_receipt_line'.tr())),
      );
      return;
    }
    final tracked =
        choice.costingMethod == 'fifo' ||
        choice.trackingType == 'batch' ||
        choice.trackingType == 'batch_expiry';
    if (tracked && _lot.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('consignment.lot_required'.tr())));
      return;
    }
    if (choice.trackingType == 'batch_expiry' && _expiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('consignment.expiry_required'.tr())),
      );
      return;
    }
    _lines.add(
      ConsignmentReceiptLineInput(
        productId: choice.productId,
        variantId: choice.variantId,
        quantity: quantity,
        manufacturerLotNumber: _lot.text.trim().isEmpty
            ? null
            : _lot.text.trim(),
        expiryDate: _expiry,
      ),
    );
    setState(() {
      _lineVariantIds.add(choice.variantId);
      _labels.add(choice.label);
      _termIndex = null;
      _quantity.text = '1';
      _lot.clear();
      _expiry = null;
    });
  }

  @override
  void dispose() {
    _number.dispose();
    _quantity.dispose();
    _lot.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.data.agreements
        .where((row) => row.status == 'active')
        .toList();
    return _SheetFrame(
      title: 'consignment.new_receipt'.tr(),
      child: Column(
        children: [
          const ConsignmentHelpCard(
            messageKey: 'consignment.guide_receipt_notice',
          ),
          const SizedBox(height: 12),
          Text('consignment.receipt_help'.tr()),
          const SizedBox(height: 12),
          DropdownMenu<String>(
            initialSelection: _agreementId,
            enableFilter: true,
            enableSearch: true,
            requestFocusOnTap: true,
            menuHeight: 420,
            expandedInsets: EdgeInsets.zero,
            leadingIcon: const Icon(LucideIcons.search),
            label: Text('consignment.search_agreement'.tr()),
            dropdownMenuEntries: [
              for (final row in active)
                DropdownMenuEntry(
                  value: row.id,
                  label:
                      '${row.agreementNumber} · ${widget.data.suppliers[row.supplierId]?.name ?? ''}',
                ),
            ],
            onSelected: _selectAgreement,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _number,
            onTap: () => _selectAll(_number),
            decoration: InputDecoration(
              labelText: 'consignment.receipt_number'.tr(),
            ),
          ),
          const SizedBox(height: 16),
          if (_loadingTerms)
            const LinearProgressIndicator()
          else ...[
            DropdownMenu<int>(
              key: ValueKey(
                'receipt-product-$_agreementId-${_lines.length}-$_termIndex',
              ),
              initialSelection: _termIndex,
              enableFilter: true,
              enableSearch: true,
              requestFocusOnTap: true,
              menuHeight: 420,
              expandedInsets: EdgeInsets.zero,
              leadingIcon: const Icon(LucideIcons.search),
              label: Text('consignment.search_product'.tr()),
              dropdownMenuEntries: [
                for (var index = 0; index < _choices.length; index++)
                  DropdownMenuEntry(value: index, label: _choices[index].label),
              ],
              onSelected: (value) => setState(() => _termIndex = value),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    onTap: () => _selectAll(_quantity),
                    keyboardType: TextInputType.numberWithOptions(
                      decimal:
                          _termIndex != null &&
                          MeasurementType.fromDb(
                                _choices[_termIndex!].measurementType,
                              ) !=
                              MeasurementType.piece,
                    ),
                    inputFormatters:
                        _termIndex != null &&
                            MeasurementType.fromDb(
                                  _choices[_termIndex!].measurementType,
                                ) ==
                                MeasurementType.piece
                        ? [FilteringTextInputFormatter.digitsOnly]
                        : null,
                    decoration: InputDecoration(
                      labelText: 'consignment.quantity'.tr(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _lot,
                    decoration: InputDecoration(
                      labelText: 'consignment.lot_optional'.tr(),
                    ),
                  ),
                ),
              ],
            ),
            if (_termIndex != null &&
                _choices[_termIndex!].trackingType == 'batch_expiry') ...[
              const SizedBox(height: 12),
              _DateTile(
                label: 'consignment.expiry_date'.tr(),
                value: _expiry ?? DateTime.now().add(const Duration(days: 365)),
                onChanged: (value) => setState(() => _expiry = value),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonalIcon(
                onPressed: _termIndex == null ? null : _addLine,
                icon: const Icon(LucideIcons.plus),
                label: Text('consignment.add_line'.tr()),
              ),
            ),
            if (_labels.isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'consignment.agreement_items_count'.tr(
                    namedArgs: {'count': '${_lines.length}'},
                  ),
                ),
              ),
              for (var index = 0; index < _labels.length; index++)
                Card(
                  child: ListTile(
                    title: Text(_labels[index]),
                    subtitle: Text(
                      '${"consignment.quantity".tr()}: ${_lines[index].quantity / (_choices.firstWhere((c) => c.variantId == _lines[index].variantId).measurementType == 'piece' ? 1 : 1000)}'
                      '${_lines[index].manufacturerLotNumber == null ? '' : ' · ${_lines[index].manufacturerLotNumber}'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'common.delete'.tr(),
                      icon: const Icon(LucideIcons.trash2),
                      onPressed: () => setState(() {
                        _labels.removeAt(index);
                        _lineVariantIds.removeAt(index);
                        _lines.removeAt(index);
                      }),
                    ),
                  ),
                ),
            ],
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: InputDecoration(labelText: 'common.notes'.tr()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('consignment.post_now'.tr()),
            subtitle: Text('consignment.guide_post_effect'.tr()),
            value: _post,
            onChanged: (value) => setState(() => _post = value),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _agreementId == null || _lines.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      _ReceiptInput(
                        agreementId: _agreementId!,
                        number: _number.text.trim(),
                        receivedAt: DateTime.now(),
                        notes: _notes.text.trim(),
                        lines: List.unmodifiable(_lines),
                        post: _post,
                      ),
                    ),
              icon: const Icon(LucideIcons.check),
              label: Text('common.save'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustodySheet extends StatefulWidget {
  const _CustodySheet({required this.data});

  final ConsignmentDashboardSnapshot data;

  @override
  State<_CustodySheet> createState() => _CustodySheetState();
}

class _CustodySheetState extends State<_CustodySheet> {
  final _number = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _liabilityCost = TextEditingController();
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  String _type = 'supplier_return';
  String _responsibility = 'supplier';
  String? _agreementId;
  String? _layerId;
  bool _loading = false;
  bool _post = true;
  List<_CustodyLayerChoice> _choices = [];
  final List<ConsignmentCustodyLineInput> _lines = [];
  final List<String> _lineLabels = [];

  @override
  void initState() {
    super.initState();
    _resetNumber();
  }

  void _resetNumber() {
    final prefix = switch (_type) {
      'loss' => 'CCL',
      'damage' => 'CCD',
      _ => 'CCR',
    };
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
    _number.text = '$prefix-$stamp';
  }

  Future<void> _selectAgreement(String? id) async {
    setState(() {
      _agreementId = id;
      _layerId = null;
      _loading = id != null;
      _choices = [];
      _lines.clear();
      _lineLabels.clear();
    });
    if (id == null) return;
    final db = sl<AppDatabase>();
    final rows =
        await (db.select(db.consignmentInventoryLayers).join([
              innerJoin(
                db.products,
                db.products.id.equalsExp(
                  db.consignmentInventoryLayers.productId,
                ),
              ),
              innerJoin(
                db.productVariants,
                db.productVariants.id.equalsExp(
                  db.consignmentInventoryLayers.variantId,
                ),
              ),
            ])..where(
              db.consignmentInventoryLayers.agreementId.equals(id) &
                  db.consignmentInventoryLayers.status.equals('open') &
                  db.consignmentInventoryLayers.remainingQuantity
                      .isBiggerThanValue(0),
            ))
            .get();
    final choices = [
      for (final row in rows)
        _CustodyLayerChoice(
          layer: row.readTable(db.consignmentInventoryLayers),
          label: _variantSearchLabel(
            productName: row.readTable(db.products).name,
            sku:
                row.readTable(db.productVariants).sku ??
                row.readTable(db.products).sku ??
                '',
            barcode:
                row.readTable(db.productVariants).barcode ??
                row.readTable(db.products).barcode ??
                '',
            variantId: row.readTable(db.productVariants).id,
          ),
        ),
    ];
    if (!mounted || _agreementId != id) return;
    setState(() {
      _choices = choices;
      _loading = false;
    });
  }

  void _changeType(String value) {
    setState(() {
      _type = value;
      if (value == 'supplier_return') _responsibility = 'supplier';
      _resetNumber();
      _liabilityCost.clear();
      _lines.clear();
      _lineLabels.clear();
    });
  }

  void _addLine() {
    final selectedId = _layerId;
    if (selectedId == null) return;
    final choice = _choices.firstWhere((row) => row.layer.id == selectedId);
    late final int quantity;
    try {
      quantity = MeasuredQuantity.parseToStored(
        _quantity.text,
        MeasurementType.fromDb(choice.layer.measurementType).majorUnit,
      );
    } on FormatException {
      _showError('consignment.quantity_invalid'.tr());
      return;
    }
    if (quantity <= 0 || quantity > choice.layer.remainingQuantity) {
      _showError('consignment.custody_quantity_exceeds_available'.tr());
      return;
    }
    if (_lines.any((line) => line.layerId == selectedId)) {
      _showError('consignment.custody_duplicate_layer'.tr());
      return;
    }

    int? liabilityUnitCents;
    if (_responsibility == 'company' &&
        _type != 'supplier_return' &&
        choice.layer.settlementBasis == 'net_sales_percentage') {
      final agreement = widget.data.agreements.firstWhere(
        (row) => row.id == _agreementId,
      );
      final currencyCode =
          widget.data.currencyCodes[agreement.currencyId] ??
          sl<CurrencyService>().currencyCode;
      final parsed = sl<MoneyInputParser>().parse(
        _liabilityCost.text,
        decimalDigits: sl<CurrencyService>().decimalDigitsForCode(currencyCode),
      );
      if (!parsed.isValid || parsed.cents <= 0) {
        _showError('consignment.custody_liability_cost_required'.tr());
        return;
      }
      liabilityUnitCents = parsed.cents;
    }

    setState(() {
      _lines.add(
        ConsignmentCustodyLineInput(
          layerId: choice.layer.id,
          quantity: quantity,
          liabilityUnitCents: liabilityUnitCents,
        ),
      );
      _lineLabels.add(
        '${choice.label} - '
        '${MeasuredQuantity.majorValue(quantity, MeasurementType.fromDb(choice.layer.measurementType))}',
      );
      _layerId = null;
      _quantity.text = '1';
      _liabilityCost.clear();
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _submit() {
    if (_agreementId == null ||
        _lines.isEmpty ||
        _number.text.trim().isEmpty ||
        _reason.text.trim().isEmpty) {
      _showError('common.required'.tr());
      return;
    }
    Navigator.pop(
      context,
      _CustodyInput(
        agreementId: _agreementId!,
        number: _number.text.trim(),
        type: _type,
        responsibility: _responsibility,
        occurredAt: DateTime.now(),
        reason: _reason.text.trim(),
        notes: _notes.text.trim(),
        lines: List.unmodifiable(_lines),
        post: _post,
      ),
    );
  }

  @override
  void dispose() {
    _number.dispose();
    _quantity.dispose();
    _liabilityCost.dispose();
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agreements = widget.data.agreements
        .where((row) => row.status != 'draft')
        .toList();
    final selected = _layerId == null
        ? null
        : _choices.firstWhere((row) => row.layer.id == _layerId);
    final companyLiability =
        _type != 'supplier_return' && _responsibility == 'company';
    final currencyCode = _agreementId == null
        ? sl<CurrencyService>().currencyCode
        : widget.data.currencyCodes[widget.data.agreements
                  .firstWhere((row) => row.id == _agreementId)
                  .currencyId] ??
              sl<CurrencyService>().currencyCode;

    return _SheetFrame(
      title: 'consignment.new_custody_movement'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ConsignmentHelpCard(
            messageKey: 'consignment.guide_custody_notice',
          ),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'consignment.custody_effect_help'.tr(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'supplier_return',
                icon: const Icon(LucideIcons.undo2),
                label: Text('consignment.custody_type_supplier_return'.tr()),
              ),
              ButtonSegment(
                value: 'loss',
                icon: const Icon(LucideIcons.packageX),
                label: Text('consignment.custody_type_loss'.tr()),
              ),
              ButtonSegment(
                value: 'damage',
                icon: const Icon(LucideIcons.triangleAlert),
                label: Text('consignment.custody_type_damage'.tr()),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (value) => _changeType(value.single),
            showSelectedIcon: false,
          ),
          if (_type != 'supplier_return') ...[
            const SizedBox(height: 12),
            Text(
              'consignment.custody_responsibility_help'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'supplier',
                  label: Text('consignment.responsibility_supplier'.tr()),
                ),
                ButtonSegment(
                  value: 'company',
                  label: Text('consignment.responsibility_company'.tr()),
                ),
              ],
              selected: {_responsibility},
              onSelectionChanged: (value) => setState(() {
                _responsibility = value.single;
                _liabilityCost.clear();
                _lines.clear();
                _lineLabels.clear();
              }),
            ),
          ],
          const SizedBox(height: 12),
          DropdownMenu<String>(
            key: ValueKey('custody-agreement-$_agreementId'),
            initialSelection: _agreementId,
            enableFilter: true,
            enableSearch: true,
            requestFocusOnTap: true,
            menuHeight: 420,
            expandedInsets: EdgeInsets.zero,
            leadingIcon: const Icon(LucideIcons.search),
            label: Text('consignment.search_agreement'.tr()),
            dropdownMenuEntries: [
              for (final row in agreements)
                DropdownMenuEntry(
                  value: row.id,
                  label:
                      '${row.agreementNumber} - '
                      '${widget.data.suppliers[row.supplierId]?.name ?? ''}',
                ),
            ],
            onSelected: _selectAgreement,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _number,
            onTap: () => _selectAll(_number),
            decoration: InputDecoration(
              labelText: 'consignment.custody_document_number'.tr(),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const LinearProgressIndicator()
          else if (_agreementId != null && _choices.isEmpty)
            Text('consignment.no_open_custody_stock'.tr())
          else if (_agreementId != null) ...[
            DropdownMenu<String>(
              key: ValueKey(
                'custody-layer-$_agreementId-$_layerId-${_lines.length}',
              ),
              initialSelection: _layerId,
              enableFilter: true,
              enableSearch: true,
              requestFocusOnTap: true,
              menuHeight: 420,
              expandedInsets: EdgeInsets.zero,
              leadingIcon: const Icon(LucideIcons.search),
              label: Text('consignment.search_custody_source'.tr()),
              dropdownMenuEntries: [
                for (final choice in _choices)
                  DropdownMenuEntry(
                    value: choice.layer.id,
                    label:
                        '${choice.label} - '
                        '${'consignment.available'.tr()}: '
                        '${MeasuredQuantity.majorValue(choice.layer.remainingQuantity, MeasurementType.fromDb(choice.layer.measurementType))} - '
                        '${choice.layer.id}',
                  ),
              ],
              onSelected: (value) => setState(() {
                _layerId = value;
                _liabilityCost.clear();
              }),
            ),
            if (selected != null) ...[
              const SizedBox(height: 8),
              Text(
                selected.layer.settlementBasis == 'fixed_unit_cost'
                    ? 'consignment.custody_fixed_cost_auto'.tr(
                        namedArgs: {
                          'amount': sl<CurrencyService>().formatForCode(
                            selected.layer.unitCostCents ?? 0,
                            currencyCode,
                          ),
                        },
                      )
                    : 'consignment.custody_percentage_value_help'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final fields = <Widget>[
                    TextField(
                      controller: _quantity,
                      onTap: () => _selectAll(_quantity),
                      keyboardType: TextInputType.numberWithOptions(
                        decimal:
                            MeasurementType.fromDb(
                              selected.layer.measurementType,
                            ) !=
                            MeasurementType.piece,
                      ),
                      decoration: InputDecoration(
                        labelText: 'consignment.quantity'.tr(),
                      ),
                    ),
                    if (companyLiability &&
                        selected.layer.settlementBasis ==
                            'net_sales_percentage')
                      TextField(
                        controller: _liabilityCost,
                        onTap: () => _selectAll(_liabilityCost),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'consignment.custody_liability_unit_cost'
                              .tr(),
                          suffixText: currencyCode,
                        ),
                      ),
                  ];
                  if (constraints.maxWidth < 560 || fields.length == 1) {
                    return Column(
                      children: [
                        for (final field in fields) ...[
                          field,
                          const SizedBox(height: 10),
                        ],
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: fields[0]),
                      const SizedBox(width: 12),
                      Expanded(child: fields[1]),
                    ],
                  );
                },
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.tonalIcon(
                  onPressed: _addLine,
                  icon: const Icon(LucideIcons.plus),
                  label: Text('consignment.add_line'.tr()),
                ),
              ),
            ],
          ],
          if (_lines.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var index = 0; index < _lines.length; index++)
              Card(
                child: ListTile(
                  leading: const Icon(LucideIcons.packageCheck),
                  title: Text(_lineLabels[index]),
                  trailing: IconButton(
                    tooltip: 'common.delete'.tr(),
                    icon: const Icon(LucideIcons.trash2),
                    onPressed: () => setState(() {
                      _lines.removeAt(index);
                      _lineLabels.removeAt(index);
                    }),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: 'consignment.custody_reason'.tr(),
              helperText: 'consignment.custody_reason_help'.tr(),
            ),
          ),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: InputDecoration(labelText: 'common.notes'.tr()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('consignment.post_now'.tr()),
            subtitle: Text(
              companyLiability
                  ? 'consignment.custody_post_company_effect'.tr()
                  : 'consignment.custody_post_supplier_effect'.tr(),
            ),
            value: _post,
            onChanged: (value) => setState(() => _post = value),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(LucideIcons.check),
            label: Text('common.save'.tr()),
          ),
        ],
      ),
    );
  }
}

DateTime _inclusiveEndOfLocalDay(DateTime value) => DateTime(
  value.year,
  value.month,
  value.day,
).add(const Duration(days: 1)).subtract(const Duration(microseconds: 1));

class _SettlementSheet extends StatefulWidget {
  const _SettlementSheet({required this.data});
  final ConsignmentDashboardSnapshot data;
  @override
  State<_SettlementSheet> createState() => _SettlementSheetState();
}

class _SettlementSheetState extends State<_SettlementSheet> {
  String? _agreementId;
  DateTime _start = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _end = _inclusiveEndOfLocalDay(DateTime.now());
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SheetFrame(
    title: 'consignment.new_settlement'.tr(),
    child: Column(
      children: [
        DropdownMenu<String>(
          initialSelection: _agreementId,
          enableFilter: true,
          enableSearch: true,
          requestFocusOnTap: true,
          menuHeight: 420,
          expandedInsets: EdgeInsets.zero,
          leadingIcon: const Icon(LucideIcons.search),
          label: Text('consignment.search_agreement'.tr()),
          dropdownMenuEntries: [
            for (final row in widget.data.agreements.where(
              (row) => row.status != 'draft',
            ))
              DropdownMenuEntry(
                value: row.id,
                label:
                    '${row.agreementNumber} · ${widget.data.suppliers[row.supplierId]?.name ?? ''}',
              ),
          ],
          onSelected: (value) => setState(() => _agreementId = value),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DateTile(
                label: 'consignment.period_start'.tr(),
                value: _start,
                onChanged: (value) => setState(() => _start = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DateTile(
                label: 'consignment.period_end'.tr(),
                value: _end,
                onChanged: (value) =>
                    setState(() => _end = _inclusiveEndOfLocalDay(value)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          maxLines: 2,
          decoration: InputDecoration(labelText: 'common.notes'.tr()),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _agreementId == null
                ? null
                : () => Navigator.pop(
                    context,
                    _SettlementInput(
                      agreementId: _agreementId!,
                      start: _start,
                      end: _end,
                      notes: _notes.text.trim(),
                    ),
                  ),
            icon: const Icon(LucideIcons.check),
            label: Text('consignment.create_draft'.tr()),
          ),
        ),
      ],
    ),
  );
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.statement, required this.currencyCode});
  final ConsignmentSettlementStatement statement;
  final String currencyCode;
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  String _method = 'cash';
  @override
  void initState() {
    super.initState();
    _amount.text = sl<CurrencyService>().minorUnitsToDecimalStringForCode(
      widget.statement.totalCents - widget.statement.paidCents,
      widget.currencyCode,
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('consignment.record_payment'.tr()),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            onTap: () => _selectAll(_amount),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'consignment.amount'.tr()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: InputDecoration(
              labelText: 'consignment.payment_method'.tr(),
            ),
            items: [
              for (final value in ['cash', 'card', 'bank_transfer'])
                DropdownMenuItem(
                  value: value,
                  child: Text('consignment.payment_$value'.tr()),
                ),
            ],
            onChanged: (value) => setState(() => _method = value!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reference,
            decoration: InputDecoration(
              labelText: 'consignment.payment_reference'.tr(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('common.cancel'.tr()),
      ),
      FilledButton(
        onPressed: () {
          final parsed = sl<MoneyInputParser>().parse(
            _amount.text,
            decimalDigits: sl<CurrencyService>().decimalDigitsForCode(
              widget.currencyCode,
            ),
          );
          if (parsed.isValid && parsed.cents > 0) {
            Navigator.pop(
              context,
              _PaymentInput(
                amountCents: parsed.cents,
                method: _method,
                reference: _reference.text.trim(),
              ),
            );
          }
        },
        child: Text('common.confirm'.tr()),
      ),
    ],
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .9,
    minChildSize: .55,
    maxChildSize: .96,
    builder: (context, controller) => Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    ),
  );
}

class _SectionScaffold extends StatelessWidget {
  const _SectionScaffold({
    required this.title,
    required this.actionLabel,
    required this.onAction,
    required this.empty,
    required this.children,
  });
  final String title, actionLabel;
  final VoidCallback? onAction;
  final bool empty;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 1100),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(LucideIcons.plus),
              label: Text(actionLabel),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (empty) const _EmptyState() else ...children,
      ],
    ),
  );
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    this.trailing,
  });
  final IconData icon;
  final String title, subtitle, status;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(child: Icon(icon, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusChip(status),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final positive = {'active', 'posted', 'paid'}.contains(status);
    return Chip(
      label: Text('consignment.status_$status'.tr()),
      avatar: Icon(
        positive
            ? LucideIcons.circleCheck
            : status == 'voided'
            ? LucideIcons.circleX
            : LucideIcons.clock3,
        size: 16,
      ),
      backgroundColor: positive
          ? colors.primaryContainer
          : colors.surfaceContainerHighest,
      side: BorderSide.none,
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: enabled ? colors.primary : colors.outline,
                size: 30,
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Icon(
                  LucideIcons.arrowRight,
                  size: 18,
                  color: enabled ? colors.primary : colors.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SafetyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(
      context,
    ).colorScheme.secondaryContainer.withValues(alpha: .55),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.shieldCheck),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'consignment.accounting_boundary'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text('consignment.accounting_boundary_desc'.tr()),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .76),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _ReportValue extends StatelessWidget {
  const _ReportValue(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 52),
    child: Center(
      child: Column(
        children: [
          Icon(
            LucideIcons.inbox,
            size: 44,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text('consignment.empty'.tr()),
        ],
      ),
    ),
  );
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final result = await showDatePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        initialDate: value,
      );
      if (result != null) {
        onChanged(result);
      }
    },
    borderRadius: BorderRadius.circular(12),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(LucideIcons.calendarDays),
      ),
      child: Text(_date(value)),
    ),
  );
}

class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SectionHeaderDelegate({required this.child});
  final Widget child;
  @override
  double get minExtent => 64;
  @override
  double get maxExtent => 64;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;
  @override
  bool shouldRebuild(covariant _SectionHeaderDelegate oldDelegate) =>
      oldDelegate.child != child;
}

class _PurchaseInvoicePickerDialog extends StatefulWidget {
  const _PurchaseInvoicePickerDialog({required this.invoices});

  final List<Purchase> invoices;

  @override
  State<_PurchaseInvoicePickerDialog> createState() =>
      _PurchaseInvoicePickerDialogState();
}

class _PurchaseInvoicePickerDialogState
    extends State<_PurchaseInvoicePickerDialog> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final rows = widget.invoices.where((invoice) {
      final text = [
        invoice.purchaseNumber,
        invoice.supplierInvoiceRef ?? '',
        DateFormat.yMd(context.locale.toString()).format(invoice.purchaseDate),
        '#${invoice.id}',
      ].join(' ').toLowerCase();
      return query.isEmpty || text.contains(query);
    }).toList();
    return AlertDialog(
      title: Text('consignment.import_one_purchase'.tr()),
      content: SizedBox(
        width: 620,
        height: 480,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'consignment.search_purchase'.tr(),
                prefixIcon: const Icon(LucideIcons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(LucideIcons.x),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'consignment.posted_purchases_only'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rows.isEmpty
                  ? Center(child: Text('consignment.no_posted_purchases'.tr()))
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final invoice = rows[index];
                        final reference = invoice.supplierInvoiceRef?.trim();
                        return ListTile(
                          leading: const Icon(LucideIcons.fileText),
                          title: Text(invoice.purchaseNumber),
                          subtitle: Text(
                            '${DateFormat.yMd(context.locale.toString()).format(invoice.purchaseDate.toLocal())}'
                            '${reference == null || reference.isEmpty ? '' : ' · $reference'}',
                          ),
                          trailing: const Icon(LucideIcons.chevronRight),
                          onTap: () => Navigator.pop(context, invoice.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
      ],
    );
  }
}

class _VariantChoice {
  const _VariantChoice({
    required this.variantId,
    required this.productId,
    required this.currencyId,
    required this.label,
    required this.trackingType,
    required this.costingMethod,
    required this.measurementType,
  });
  final int variantId, productId, currencyId;
  final String label, trackingType, costingMethod, measurementType;
}

class _AgreementTermChoice {
  const _AgreementTermChoice({
    required this.productId,
    required this.variantId,
    required this.currencyId,
  });
  final int productId;
  final int? variantId;
  final int currencyId;
}

class _AgreementInput {
  const _AgreementInput({
    required this.supplierId,
    required this.currencyId,
    required this.number,
    required this.effectiveFrom,
    required this.frequency,
    required this.paymentTermsDays,
    required this.taxRateBps,
    required this.taxInclusive,
    required this.notes,
    required this.terms,
    required this.supplierMode,
    required this.activate,
  });
  final int supplierId, currencyId, paymentTermsDays, taxRateBps;
  final String number, frequency, notes, supplierMode;
  final DateTime effectiveFrom;
  final bool taxInclusive, activate;
  final List<ConsignmentAgreementTermInput> terms;
}

class _ReceiptInput {
  const _ReceiptInput({
    required this.agreementId,
    required this.number,
    required this.receivedAt,
    required this.notes,
    required this.lines,
    required this.post,
  });
  final String agreementId, number, notes;
  final DateTime receivedAt;
  final List<ConsignmentReceiptLineInput> lines;
  final bool post;
}

class _ConversionInput {
  const _ConversionInput({
    required this.agreementId,
    required this.number,
    required this.evidenceReference,
    required this.convertedAt,
    required this.notes,
    required this.lines,
  });

  final String agreementId, number, evidenceReference, notes;
  final DateTime convertedAt;
  final List<ConsignmentOwnershipConversionLineInput> lines;
}

class _ConversionSourceChoice {
  const _ConversionSourceChoice({
    required this.key,
    required this.source,
    required this.label,
    required this.unitCostCents,
  });

  final String key;
  final InventoryStockSourceBalance source;
  final String label;
  final int unitCostCents;
}

class _CustodyInput {
  const _CustodyInput({
    required this.agreementId,
    required this.number,
    required this.type,
    required this.responsibility,
    required this.occurredAt,
    required this.reason,
    required this.notes,
    required this.lines,
    required this.post,
  });

  final String agreementId, number, type, responsibility, reason, notes;
  final DateTime occurredAt;
  final List<ConsignmentCustodyLineInput> lines;
  final bool post;
}

class _CustodyLayerChoice {
  const _CustodyLayerChoice({required this.layer, required this.label});

  final ConsignmentInventoryLayer layer;
  final String label;
}

class _SettlementInput {
  const _SettlementInput({
    required this.agreementId,
    required this.start,
    required this.end,
    required this.notes,
  });
  final String agreementId, notes;
  final DateTime start, end;
}

class _PaymentInput {
  const _PaymentInput({
    required this.amountCents,
    required this.method,
    required this.reference,
  });
  final int amountCents;
  final String method, reference;
}

String _supplierSearchLabel(Supplier supplier) {
  final code = supplier.productCode?.trim();
  return [
    supplier.name,
    if (code != null && code.isNotEmpty) code,
    '#${supplier.id}',
  ].join(' · ');
}

String _variantSearchLabel({
  required String productName,
  required String sku,
  required String barcode,
  required int variantId,
}) => [
  productName,
  if (sku.trim().isNotEmpty) sku.trim(),
  if (barcode.trim().isNotEmpty) barcode.trim(),
  '#$variantId',
].join(' · ');

void _selectAll(TextEditingController controller) {
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: controller.text.length,
  );
}

String _basisPointsToPercent(int basisPoints) {
  final whole = basisPoints ~/ 100;
  final fraction = basisPoints.abs() % 100;
  if (fraction == 0) return whole.toString();
  return '$whole.${fraction.toString().padLeft(2, '0').replaceFirst(RegExp(r'0+$'), '')}';
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'common.required'.tr() : null;
String _date(DateTime value) => DateFormat.yMMMd().format(value.toLocal());
String _localizedMoneyTotals(Map<String, int> values) {
  if (values.isEmpty) return '—';
  final service = sl<CurrencyService>();
  final entries = values.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries
      .map((entry) => service.formatForCode(entry.value, entry.key))
      .join(' • ');
}
