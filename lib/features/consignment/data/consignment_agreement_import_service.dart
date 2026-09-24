import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/measurement/measurement.dart';
import '../../../core/services/inventory/supplier_product_identity_service.dart';
import 'consignment_agreement_service.dart';

class ConsignmentPurchaseImportItem {
  const ConsignmentPurchaseImportItem({
    required this.productId,
    required this.variantId,
    required this.unitCostCents,
    required this.sourcePurchaseId,
    required this.sourcePurchaseNumber,
    required this.sourcePurchaseDate,
    required this.costVariedAcrossPurchases,
  });

  final int productId;
  final int variantId;
  final int unitCostCents;
  final int sourcePurchaseId;
  final String sourcePurchaseNumber;
  final DateTime sourcePurchaseDate;
  final bool costVariedAcrossPurchases;
}

class ConsignmentPurchaseImportResult {
  const ConsignmentPurchaseImportResult({
    required this.items,
    required this.skippedLines,
  });

  final List<ConsignmentPurchaseImportItem> items;
  final int skippedLines;

  int get variedCostItems =>
      items.where((item) => item.costVariedAcrossPurchases).length;
}

/// Uses posted purchase invoices only as a data-entry template for agreement
/// terms. It never changes a purchase, stock ownership, AP, tax or journals.
class ConsignmentAgreementImportService {
  ConsignmentAgreementImportService(this.db);

  final AppDatabase db;

  /// Converts an imported invoice item into the commercial term selected for
  /// the whole agreement. Fixed terms keep the invoice's net inventory cost;
  /// percentage terms use the single supplier share entered by the user.
  static ConsignmentAgreementTermInput toAgreementTerm(
    ConsignmentPurchaseImportItem item, {
    required String settlementBasis,
    int? supplierShareBps,
  }) {
    if (settlementBasis == 'fixed_unit_cost') {
      return ConsignmentAgreementTermInput.fixedCost(
        productId: item.productId,
        variantId: item.variantId,
        amountCents: item.unitCostCents,
      );
    }
    if (settlementBasis == 'net_sales_percentage' &&
        supplierShareBps != null &&
        supplierShareBps >= 0 &&
        supplierShareBps <= 10000) {
      return ConsignmentAgreementTermInput.salesPercentage(
        productId: item.productId,
        variantId: item.variantId,
        shareBps: supplierShareBps,
      );
    }
    throw ArgumentError('A supplier share from 0% to 100% is required.');
  }

  Future<List<Purchase>> listPostedPurchases({
    required int supplierId,
    required int currencyId,
  }) =>
      (db.select(db.purchases)
            ..where(
              (row) =>
                  row.supplierId.equals(supplierId) &
                  row.currencyId.equals(currencyId) &
                  row.status.equals('posted'),
            )
            ..orderBy([
              (row) => OrderingTerm.desc(row.purchaseDate),
              (row) => OrderingTerm.desc(row.id),
            ]))
          .get();

  Future<ConsignmentPurchaseImportResult> buildTerms({
    required int supplierId,
    required int currencyId,
    int? purchaseId,
  }) => db.transaction(() async {
    final supplier = await (db.select(
      db.suppliers,
    )..where((row) => row.id.equals(supplierId))).getSingleOrNull();
    if (supplier == null || !supplier.isActive) {
      throw StateError('Consignment import requires an active supplier.');
    }
    if (supplier.currencyId != currencyId) {
      throw StateError('Consignment import currency differs from supplier.');
    }

    final purchaseFilter = purchaseId == null ? '' : ' AND pu.id=?';
    final variables = <Variable<Object>>[
      Variable.withInt(supplierId),
      Variable.withInt(currencyId),
      if (purchaseId != null) Variable.withInt(purchaseId),
    ];
    final rows = await db.customSelect(
      '''SELECT pu.id AS purchase_id,pu.purchase_number,pu.purchase_date,
      pi.product_id,pi.variant_id,pi.quantity,pi.quantity_scale,
      pi.subtotal_cents,pi.discount_cents,pi.inventory_value_at_post_cents
      FROM purchases pu
      JOIN purchase_items pi ON pi.purchase_id=pu.id
      JOIN products p ON p.id=pi.product_id
      WHERE pu.supplier_id=? AND pu.currency_id=? AND pu.status='posted'
        AND p.is_active=1 AND p.track_inventory=1$purchaseFilter
      ORDER BY pu.purchase_date DESC,pu.id DESC,pi.id ASC''',
      variables: variables,
    ).get();

    final resolver = SupplierProductIdentityService(db);
    final products = <int, Product>{};
    final grouped = <String, _InvoiceVariantAccumulator>{};
    var skipped = 0;
    for (final row in rows) {
      final productId = row.read<int>('product_id');
      final product =
          products[productId] ??
          await (db.select(
            db.products,
          )..where((item) => item.id.equals(productId))).getSingle();
      products[productId] = product;
      int variantId;
      try {
        variantId = await resolver.resolveCanonicalVariant(
          product: product,
          variantId: row.readNullable<int>('variant_id'),
        );
      } catch (_) {
        skipped++;
        continue;
      }
      final quantity = row.read<int>('quantity');
      final quantityScale = row.read<int>('quantity_scale');
      if (quantity <= 0 || quantityScale <= 0) {
        skipped++;
        continue;
      }
      final postedValue = row.readNullable<int>(
        'inventory_value_at_post_cents',
      );
      final fallbackValue =
          row.read<int>('subtotal_cents') - row.read<int>('discount_cents');
      final inventoryValue =
          postedValue ?? (fallbackValue < 0 ? 0 : fallbackValue);
      final invoiceId = row.read<int>('purchase_id');
      final key = '$invoiceId:$variantId';
      final accumulator = grouped.putIfAbsent(
        key,
        () => _InvoiceVariantAccumulator(
          purchaseId: invoiceId,
          purchaseNumber: row.read<String>('purchase_number'),
          purchaseDate: row.read<DateTime>('purchase_date'),
          productId: productId,
          variantId: variantId,
          quantityScale: quantityScale,
        ),
      );
      if (accumulator.quantityScale != quantityScale) {
        skipped++;
        continue;
      }
      accumulator.quantity += quantity;
      accumulator.inventoryValueCents += inventoryValue;
    }

    final candidatesByVariant = <int, List<_ImportCandidate>>{};
    for (final accumulator in grouped.values) {
      if (accumulator.quantity <= 0) continue;
      final unitCost = MeasuredAmount.unitCentsFromTotal(
        totalCents: accumulator.inventoryValueCents,
        quantity: accumulator.quantity,
        quantityScale: accumulator.quantityScale,
      );
      candidatesByVariant
          .putIfAbsent(accumulator.variantId, () => [])
          .add(
            _ImportCandidate(
              purchaseId: accumulator.purchaseId,
              purchaseNumber: accumulator.purchaseNumber,
              purchaseDate: accumulator.purchaseDate,
              productId: accumulator.productId,
              variantId: accumulator.variantId,
              unitCostCents: unitCost,
            ),
          );
    }

    final items = <ConsignmentPurchaseImportItem>[];
    for (final candidates in candidatesByVariant.values) {
      candidates.sort((a, b) {
        final date = b.purchaseDate.compareTo(a.purchaseDate);
        return date != 0 ? date : b.purchaseId.compareTo(a.purchaseId);
      });
      final latest = candidates.first;
      items.add(
        ConsignmentPurchaseImportItem(
          productId: latest.productId,
          variantId: latest.variantId,
          unitCostCents: latest.unitCostCents,
          sourcePurchaseId: latest.purchaseId,
          sourcePurchaseNumber: latest.purchaseNumber,
          sourcePurchaseDate: latest.purchaseDate,
          costVariedAcrossPurchases:
              candidates.map((row) => row.unitCostCents).toSet().length > 1,
        ),
      );
    }
    items.sort((a, b) {
      final product = a.productId.compareTo(b.productId);
      return product != 0 ? product : a.variantId.compareTo(b.variantId);
    });
    return ConsignmentPurchaseImportResult(
      items: List.unmodifiable(items),
      skippedLines: skipped,
    );
  });
}

class _InvoiceVariantAccumulator {
  _InvoiceVariantAccumulator({
    required this.purchaseId,
    required this.purchaseNumber,
    required this.purchaseDate,
    required this.productId,
    required this.variantId,
    required this.quantityScale,
  });

  final int purchaseId;
  final String purchaseNumber;
  final DateTime purchaseDate;
  final int productId;
  final int variantId;
  final int quantityScale;
  int quantity = 0;
  int inventoryValueCents = 0;
}

class _ImportCandidate {
  const _ImportCandidate({
    required this.purchaseId,
    required this.purchaseNumber,
    required this.purchaseDate,
    required this.productId,
    required this.variantId,
    required this.unitCostCents,
  });

  final int purchaseId;
  final String purchaseNumber;
  final DateTime purchaseDate;
  final int productId;
  final int variantId;
  final int unitCostCents;
}
