/// Stable, presentation-independent identity for an inventory source selected
/// by a sale line. The key deliberately excludes mutable labels such as the
/// supplier name and barcode.
class SaleStockSourceRef {
  const SaleStockSourceRef({
    required this.productId,
    required this.variantId,
    this.supplierIdentityId,
    this.consignmentLayerId,
  });

  final int productId;
  final int variantId;
  final int? supplierIdentityId;
  final String? consignmentLayerId;

  String get reservationKey {
    final consignment = consignmentLayerId?.trim();
    if (consignment != null && consignment.isNotEmpty) {
      return 'consignment:$consignment';
    }
    if (supplierIdentityId != null) {
      return 'supplier-identity:$supplierIdentityId';
    }
    // Legacy/unverified stock has no immutable supplier identity. Keep its
    // reservation isolated by product and operational variant.
    return 'unverified:$productId:$variantId';
  }
}

class SaleStockSourceReservation {
  const SaleStockSourceReservation({
    required this.lineId,
    required this.source,
    required this.quantity,
  });

  final String lineId;
  final SaleStockSourceRef source;
  final int quantity;
}

class SaleStockSourceReservationLedger {
  const SaleStockSourceReservationLedger._();

  static int reservedQuantity(
    Iterable<SaleStockSourceReservation> reservations,
    SaleStockSourceRef source, {
    String? excludingLineId,
  }) {
    final key = source.reservationKey;
    return reservations
        .where(
          (entry) =>
              entry.lineId != excludingLineId &&
              entry.source.reservationKey == key,
        )
        .fold<int>(0, (sum, entry) => sum + entry.quantity);
  }

  static int remainingQuantity({
    required int availableQuantity,
    required Iterable<SaleStockSourceReservation> reservations,
    required SaleStockSourceRef source,
    String? excludingLineId,
    int pendingQuantity = 0,
  }) {
    final reserved = reservedQuantity(
      reservations,
      source,
      excludingLineId: excludingLineId,
    );
    final remaining = availableQuantity - reserved - pendingQuantity;
    return remaining > 0 ? remaining : 0;
  }
}
