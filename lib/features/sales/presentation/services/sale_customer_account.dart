import '../../../../core/database/app_database.dart' show Customer;
import '../../../../core/services/lan/lan_network_service.dart';

class SaleCustomerAccount {
  const SaleCustomerAccount({
    required this.currencyId,
    required this.balanceCents,
    required this.pointsBalance,
  });
  final int currencyId;
  final int balanceCents;
  final int pointsBalance;
}

/// An enrolled workstation always reads the branch account, including when its
/// session has expired. Authentication failure must never select local data.
Future<SaleCustomerAccount?> loadSaleCustomerAccount({
  required int customerId,
  required LanNetworkService lan,
  required Future<Customer?> Function(int) loadLocal,
}) async {
  if (lan.snapshot.mode == LanMode.client) {
    final account = await lan.fetchRemoteCustomerCheckout(customerId);
    return SaleCustomerAccount(
      currencyId: account.currencyId,
      balanceCents: account.balanceCents,
      pointsBalance: account.pointsBalance,
    );
  }
  final customer = await loadLocal(customerId);
  if (customer == null) return null;
  return SaleCustomerAccount(
    currencyId: customer.currencyId,
    balanceCents: customer.balanceCents.toBigInt().toInt(),
    pointsBalance: customer.loyaltyPointsBalance,
  );
}
