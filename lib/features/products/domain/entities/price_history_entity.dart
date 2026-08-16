import 'package:equatable/equatable.dart';

class PriceHistory extends Equatable {
  final int id;
  final int productId;
  final int? variantId;
  final int oldCostCents;
  final int newCostCents;
  final int oldPriceCents;
  final int newPriceCents;
  final int? oldWholesalePriceCents;
  final int? newWholesalePriceCents;
  final int userId;
  final String? changeReason;
  final DateTime createdAt;

  const PriceHistory({
    required this.id,
    required this.productId,
    this.variantId,
    required this.oldCostCents,
    required this.newCostCents,
    required this.oldPriceCents,
    required this.newPriceCents,
    this.oldWholesalePriceCents,
    this.newWholesalePriceCents,
    required this.userId,
    this.changeReason,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
    id,
    productId,
    variantId,
    oldCostCents,
    newCostCents,
    oldPriceCents,
    newPriceCents,
    oldWholesalePriceCents,
    newWholesalePriceCents,
    userId,
    changeReason,
    createdAt,
  ];
}
