import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/daos/cheque_instrument_dao.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/cheque_management_service.dart';

class PartyChequeAlertsSection extends StatelessWidget {
  final String partyType;
  final int partyId;

  const PartyChequeAlertsSection({
    super.key,
    required this.partyType,
    required this.partyId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return StreamBuilder<List<ChequeRegisterEntry>>(
      stream: sl<ChequeManagementService>().watchRegister().map((entries) {
        final alerts = entries
            .where((entry) {
              final cheque = entry.instrument;
              final unresolvedBounce =
                  cheque.status == ChequeInstrumentStatus.bounced &&
                  cheque.resolvedAt == null;
              return cheque.partyType == partyType &&
                  cheque.partyId == partyId &&
                  (ChequeInstrumentStatus.open.contains(cheque.status) ||
                      unresolvedBounce);
            })
            .toList(growable: false);
        alerts.sort((a, b) {
          final aBounced =
              a.instrument.status == ChequeInstrumentStatus.bounced;
          final bBounced =
              b.instrument.status == ChequeInstrumentStatus.bounced;
          if (aBounced != bBounced) return aBounced ? -1 : 1;
          return a.instrument.dueDate.compareTo(b.instrument.dueDate);
        });
        return alerts;
      }),
      builder: (context, snapshot) {
        final alerts = snapshot.data ?? const <ChequeRegisterEntry>[];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.notification_important_outlined,
                      size: 19,
                      color:
                          alerts.any(
                            (e) =>
                                e.instrument.status ==
                                ChequeInstrumentStatus.bounced,
                          )
                          ? cs.error
                          : cs.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'cheques.party_alerts'.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (alerts.isNotEmpty)
                      Badge(label: Text('${alerts.length}')),
                  ],
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (alerts.isEmpty)
                  Text(
                    'cheques.no_party_alerts'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  )
                else ...[
                  ...alerts
                      .take(5)
                      .map((entry) => _PartyChequeAlertTile(entry: entry)),
                  if (alerts.length > 5)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: () => context.push('/cheques'),
                        child: Text(
                          'cheques.show_all_alerts'.tr(
                            args: ['${alerts.length}'],
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PartyChequeAlertTile extends StatelessWidget {
  final ChequeRegisterEntry entry;

  const _PartyChequeAlertTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cheque = entry.instrument;
    final cs = Theme.of(context).colorScheme;
    final bounced = cheque.status == ChequeInstrumentStatus.bounced;
    final overdue =
        !bounced &&
        cheque.dueDate.isBefore(
          DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
          ),
        );
    final color = bounced
        ? cs.error
        : overdue
        ? Colors.orange
        : cs.primary;
    final amount = cheque.amountCents.toBigInt().toInt() / 100;
    final chequeNumber = cheque.chequeNumber?.trim().isNotEmpty == true
        ? cheque.chequeNumber!.trim()
        : '#${cheque.id}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => context.push(
          bounced ? '/cheques?status=bounced' : '/cheques?status=open',
        ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    bounced
                        ? Icons.warning_amber_rounded
                        : Icons.payments_outlined,
                    color: color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _sourceLabel(cheque.sourceTable),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${entry.currencySymbol}${amount.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 34, top: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${'cheques.invoice_number'.tr()}: ${entry.referenceNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${'cheques.number'.tr()}: $chequeNumber',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bounced
                          ? 'cheques.alert_bounced_unresolved'.tr()
                          : overdue
                          ? 'cheques.alert_overdue'.tr()
                          : 'cheques.alert_due'.tr(
                              args: [
                                DateFormat('dd/MM/yyyy').format(cheque.dueDate),
                              ],
                            ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sourceLabel(String source) => switch (source) {
    'sale' => 'cheques.source_sale'.tr(),
    'purchase' => 'cheques.source_purchase'.tr(),
    'sale_return' => 'cheques.source_sale_return'.tr(),
    'purchase_return' => 'cheques.source_purchase_return'.tr(),
    'sale_return_adjustment' => 'cheques.source_sale_return_adjustment'.tr(),
    'purchase_return_adjustment' =>
      'cheques.source_purchase_return_adjustment'.tr(),
    _ => source,
  };
}
