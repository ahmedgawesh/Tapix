/// Only document headers and batches have independent locations in this phase.
/// Item lines, payments and batch consumptions inherit their parent's location.
enum BusinessDocumentType {
  sale('sales'),
  purchase('purchases'),
  saleReturn('sale_returns'),
  purchaseReturn('purchase_returns'),
  saleReturnAdjustment('sale_return_adjustments'),
  purchaseReturnAdjustment('purchase_return_adjustments'),
  inventoryAdjustment('inventory_adjustments'),
  productBatch('product_batches'),
  journalEntry('journal_entries');

  const BusinessDocumentType(this.sourceTable);
  final String sourceTable;
}
