import '../void_impact_analyzer.dart';

/// Carries the server's read-only cancellation preview without consulting a
/// workstation's unrelated local database. Quantities and money remain ints.
Map<String, dynamic> lanVoidImpactToJson(VoidImpactReport report) => {
  'side': report.side,
  'documentExists': report.documentExists,
  'documentStatus': report.documentStatus,
  'linkedReturns': [
    for (final value in report.linkedReturns)
      {
        'returnId': value.returnId,
        'returnNumber': value.returnNumber,
        'totalCents': value.totalCents,
        'status': value.status,
      },
  ],
  'adjustmentAllocatedQty': report.adjustmentAllocatedQty,
  'entangledAdjustmentReturns': [
    for (final value in report.entangledAdjustmentReturns)
      {
        'returnId': value.returnId,
        'returnNumber': value.returnNumber,
        'totalCents': value.totalCents,
        'refundMethod': value.refundMethod,
      },
  ],
  'negativeStockRisks': [
    for (final value in report.negativeStockRisks)
      {
        'productId': value.productId,
        'variantId': value.variantId,
        'currentStock': value.currentStock,
        'requiredQuantity': value.requiredQuantity,
      },
  ],
  'estimatedArAdjustmentCents': report.estimatedArAdjustmentCents,
  'estimatedInventoryAdjustmentCents': report.estimatedInventoryAdjustmentCents,
};

VoidImpactReport lanVoidImpactFromJson(Map<String, dynamic> json) =>
    VoidImpactReport(
      side: json['side'] as String,
      documentExists: json['documentExists'] as bool,
      documentStatus: json['documentStatus'] as String,
      linkedReturns: [
        for (final value in json['linkedReturns'] as List)
          LinkedReturnEntry(
            returnId: value['returnId'] as int,
            returnNumber: value['returnNumber'] as String,
            totalCents: value['totalCents'] as int,
            status: value['status'] as String,
          ),
      ],
      adjustmentAllocatedQty: json['adjustmentAllocatedQty'] as int,
      entangledAdjustmentReturns: [
        for (final value in json['entangledAdjustmentReturns'] as List)
          EntangledAdjustmentReturn(
            returnId: value['returnId'] as int,
            returnNumber: value['returnNumber'] as String,
            totalCents: value['totalCents'] as int,
            refundMethod: value['refundMethod'] as String,
          ),
      ],
      negativeStockRisks: [
        for (final value in json['negativeStockRisks'] as List)
          NegativeStockRisk(
            productId: value['productId'] as int,
            variantId: value['variantId'] as int?,
            currentStock: value['currentStock'] as int,
            requiredQuantity: value['requiredQuantity'] as int,
          ),
      ],
      estimatedArAdjustmentCents: json['estimatedArAdjustmentCents'] as int,
      estimatedInventoryAdjustmentCents:
          json['estimatedInventoryAdjustmentCents'] as int,
    );
