
import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

class PurchaseEntity extends Equatable {
  final int id;
  final String purchaseNumber;
  final int supplierId;
  final Decimal subtotalCents;
  final Decimal taxCents;
  final Decimal totalCents;
  final int currencyId;
  final String status;
  final DateTime purchaseDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PurchaseEntity({
    required this.id,
    required this.purchaseNumber,
    required this.supplierId,
    required this.subtotalCents,
    required this.taxCents,
    required this.totalCents,
    required this.currencyId,
    required this.status,
    required this.purchaseDate,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPending => status == 'pending' || status == 'draft';

  @override
  List<Object?> get props => [
        id,
        purchaseNumber,
        supplierId,
        subtotalCents,
        taxCents,
        totalCents,
        currencyId,
        status,
        purchaseDate,
        createdAt,
        updatedAt,
      ];
}

class PurchaseItemEntity extends Equatable {
  final int id;
  final int purchaseId;
  final int productId;
  final int? variantId;
  final int quantity;
  final Decimal unitCostCents;
  final Decimal subtotalCents;
  final Decimal taxCents;
  final Decimal totalCents;
  final DateTime createdAt;

  const PurchaseItemEntity({
    required this.id,
    required this.purchaseId,
    required this.productId,
    this.variantId,
    required this.quantity,
    required this.unitCostCents,
    required this.subtotalCents,
    required this.taxCents,
    required this.totalCents,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        purchaseId,
        productId,
        variantId,
        quantity,
        unitCostCents,
        subtotalCents,
        taxCents,
        totalCents,
        createdAt,
      ];
}

