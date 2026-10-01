import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Loads the committed balance after saving; never guesses earned points from
/// the cart or treats a failed request as a zero balance.
class SaleCustomerPointsSummary extends StatefulWidget {
  const SaleCustomerPointsSummary({super.key, required this.load});
  final Future<int> Function() load;

  @override
  State<SaleCustomerPointsSummary> createState() =>
      _SaleCustomerPointsSummaryState();
}

class _SaleCustomerPointsSummaryState extends State<SaleCustomerPointsSummary> {
  late Future<int> _request = widget.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
    future: _request,
    builder: (context, snapshot) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: snapshot.connectionState != ConnectionState.done
          ? const LinearProgressIndicator()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  snapshot.hasError || snapshot.data == null
                      ? 'sales.checkout_customer_unavailable'.tr()
                      : '${'sales.loyalty_points_balance'.tr()}: ${snapshot.data}',
                  textAlign: TextAlign.center,
                ),
                if (snapshot.hasError || snapshot.data == null)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _request = widget.load();
                    }),
                    icon: const Icon(Icons.refresh),
                    label: Text('common.retry'.tr()),
                  ),
              ],
            ),
    ),
  );
}
