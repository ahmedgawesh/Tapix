import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/party_account_payment_service.dart';
import '../../../../core/utils/app_date_formatter.dart';
import '../widgets/account_payment_allocation_dialog.dart';

class PartyUnappliedBalancesSection extends StatelessWidget {
  final String partyType;
  final int partyId;
  final int? userId;

  const PartyUnappliedBalancesSection({
    super.key,
    required this.partyType,
    required this.partyId,
    this.userId,
  });

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<PartyUnappliedBalance>>(
    stream: sl<PartyAccountPaymentService>().watchUnappliedForParty(
      partyType: partyType,
      partyId: partyId,
    ),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting ||
          snapshot.hasError ||
          (snapshot.data?.isEmpty ?? true)) {
        return const SizedBox.shrink();
      }
      final balances = snapshot.data!;
      final cs = Theme.of(context).colorScheme;
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.primary.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.walletCards, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'cheques.party_unapplied_balances'.tr(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Badge(label: Text('${balances.length}')),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'cheques.party_unapplied_hint'.tr(),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              ...balances.map(
                (balance) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(LucideIcons.fileCheck2),
                  title: Text(
                    '${'cheques.number'.tr()}: ${balance.chequeNumber}',
                  ),
                  subtitle: Text(
                    '${AppDateFormatter.date(balance.recognizedAt)} • '
                    '${'cheques.advance_applied'.tr()}: '
                    '${_money(balance.appliedCents, balance.currencySymbol)}',
                  ),
                  trailing: Text(
                    _money(balance.availableCents, balance.currencySymbol),
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () => showAccountPaymentAllocationDialog(
                    context,
                    chequeId: balance.chequeId,
                    userId: userId,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _money(int cents, String symbol) =>
    '$symbol${(cents / 100).toStringAsFixed(2)}';
