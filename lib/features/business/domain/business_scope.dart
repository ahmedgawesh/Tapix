/// The durable owner of an existing single-branch database. The identifiers
/// survive restarts and backups; none is an authentication credential.
class BusinessScope {
  const BusinessScope({
    required this.organizationId,
    required this.branchId,
    required this.warehouseId,
    required this.databaseId,
    required this.organizationName,
    required this.branchName,
    required this.warehouseName,
  });

  final String organizationId;
  final String branchId;
  final String warehouseId;
  final String databaseId;
  final String organizationName;
  final String branchName;
  final String warehouseName;
}

class PrimaryWarehouseStock {
  const PrimaryWarehouseStock({
    required this.warehouseId,
    required this.productId,
    required this.variantId,
    required this.quantity,
    required this.quantityScale,
    required this.unitCostCents,
    required this.isActive,
  });

  final String warehouseId;
  final int productId;
  final int variantId;

  /// Stored integer units, never rounded during migration/projection.
  final int quantity;
  final int quantityScale;

  /// Existing variant cost; this is not a recomputation of FIFO valuation.
  final int unitCostCents;
  final bool isActive;
}
