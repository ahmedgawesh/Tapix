import 'dart:ui' as ui;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/lan/lan_business_models.dart';

/// Keeps remote financial data out of the device's unrelated local database.
class RemoteCustomerCheckoutCard extends StatefulWidget {
  const RemoteCustomerCheckoutCard({
    super.key,
    required this.customerId,
    required this.currencyId,
    required this.invoiceTotalCents,
    required this.paidAmountCents,
    required this.currencyService,
    required this.load,
  });
  final int customerId, currencyId, invoiceTotalCents, paidAmountCents;
  final CurrencyService currencyService;
  final Future<LanCustomerCheckout> Function(int) load;
  @override
  State<RemoteCustomerCheckoutCard> createState() =>
      _RemoteCustomerCheckoutCardState();
}

class _RemoteCustomerCheckoutCardState
    extends State<RemoteCustomerCheckoutCard> {
  late Future<LanCustomerCheckout> _request = widget.load(widget.customerId);
  @override
  void didUpdateWidget(covariant RemoteCustomerCheckoutCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customerId != widget.customerId) {
      _request = widget.load(widget.customerId);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<LanCustomerCheckout>(
    future: _request,
    builder: (context, snapshot) {
      final colors = Theme.of(context).colorScheme;
      final data = snapshot.data;
      final waiting = snapshot.connectionState != ConnectionState.done;
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'sales.customer_balance'.tr(),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'common.refresh'.tr(),
                    onPressed: waiting
                        ? null
                        : () => setState(() {
                            _request = widget.load(widget.customerId);
                          }),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (waiting)
                const LinearProgressIndicator()
              else if (snapshot.hasError ||
                  data == null ||
                  data.customerId != widget.customerId)
                Text(
                  'sales.checkout_customer_unavailable'.tr(),
                  style: TextStyle(color: colors.error),
                )
              else ...[
                if (data.currencyId != widget.currencyId ||
                    data.currencyCode != widget.currencyService.currencyCode)
                  Text(
                    'sales.checkout_currency_mismatch'.tr(),
                    style: TextStyle(color: colors.error),
                  )
                else
                  Text(
                    '${widget.currencyService.format(data.balanceCents)} → ${widget.currencyService.format(data.balanceCents + widget.invoiceTotalCents - widget.paidAmountCents)}',
                    textDirection: ui.TextDirection.ltr,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: colors.primary),
                  ),
                const SizedBox(height: 8),
                Text(
                  '${'sales.loyalty_points'.tr()}: ${data.pointsBalance}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'sales.checkout_points_readonly'.tr(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
