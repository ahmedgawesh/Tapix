import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import 'supplier_identity_rules.dart';
import 'supplier_product_identity_service.dart';
import 'supplier_purchase_source_policy.dart';

/// Preview port used by the form; a preview must never issue or reserve a SKU.
abstract interface class PurchaseSupplierSourcePreviewer {
  Future<SupplierIdentityPreview> preview({
    required int supplierId,
    required int productId,
    int? variantId,
  });
}

class PurchaseSupplierSourceService implements PurchaseSupplierSourcePreviewer {
  PurchaseSupplierSourceService(this.db);
  final AppDatabase db;

  Future<void> _assertCanWrite() async {
    if (!SupplierPurchaseSourcePolicy.buildAllowsWrites) {
      throw const SupplierIdentityException(
        'supplier_purchase.development_only',
      );
    }
    if (await db.settingsDao.getSetting('lan.mode') == 'client') {
      throw const SupplierIdentityException(
        'supplier_identity.master_required',
      );
    }
  }

  @override
  Future<SupplierIdentityPreview> preview({
    required int supplierId,
    required int productId,
    int? variantId,
  }) async {
    await _assertCanWrite();
    return SupplierProductIdentityService(db).preview(
      supplierId: supplierId,
      productId: productId,
      variantId: variantId,
    );
  }

  /// Called INSIDE PurchaseDao's document transaction. The caller's persisted
  /// request, not the current settings or a supplied identity ID, is authority.
  Future<PurchaseItemsCompanion> bind({
    required int supplierId,
    required PurchaseItemsCompanion item,
  }) async {
    final requested =
        item.supplierIdentityRequested.present &&
        item.supplierIdentityRequested.value;
    if (!requested) {
      if (item.supplierIdentityId.present &&
          item.supplierIdentityId.value != null) {
        throw const SupplierIdentityException(
          'supplier_purchase.source_mismatch',
        );
      }
      return item;
    }
    await _assertCanWrite();
    if (!item.productId.present) {
      throw const SupplierIdentityException(
        'supplier_purchase.source_mismatch',
      );
    }
    final product = await (db.select(
      db.products,
    )..where((p) => p.id.equals(item.productId.value))).getSingleOrNull();
    if (product == null || !product.trackInventory) {
      throw const SupplierIdentityException(
        'supplier_purchase.untracked_product',
      );
    }
    final identity = await SupplierProductIdentityService(db).ensureIssued(
      supplierId: supplierId,
      productId: product.id,
      variantId: item.variantId.present ? item.variantId.value : null,
    );
    // Never trust an externally supplied ID: reject an inconsistent value.
    if (item.supplierIdentityId.present &&
        item.supplierIdentityId.value != null &&
        item.supplierIdentityId.value != identity.id) {
      throw const SupplierIdentityException(
        'supplier_purchase.source_mismatch',
      );
    }
    return item.copyWith(supplierIdentityId: Value(identity.id));
  }

  /// Posting checks the SAVED binding, not a fresh prefix/base-SKU composition.
  /// All quantity, cost, lot and journal work remains in the existing pipeline.
  Future<void> validateForPosting(
    Purchase purchase,
    List<PurchaseItem> items,
  ) async {
    for (final item in items) {
      if (!item.supplierIdentityRequested && item.supplierIdentityId == null) {
        continue;
      }
      await _assertCanWrite();
      final identityId = item.supplierIdentityId;
      if (!item.supplierIdentityRequested || identityId == null) {
        throw const SupplierIdentityException(
          'supplier_purchase.source_mismatch',
        );
      }
      final identity = await SupplierProductIdentityService(
        db,
      ).getById(identityId);
      final product = await (db.select(
        db.products,
      )..where((p) => p.id.equals(item.productId))).getSingle();
      final supplier = await (db.select(
        db.suppliers,
      )..where((s) => s.id.equals(purchase.supplierId))).getSingle();
      if (!supplier.isActive || !product.isActive || !product.trackInventory) {
        throw const SupplierIdentityException(
          'supplier_identity.inactive_source',
        );
      }
      final canonical = await SupplierProductIdentityService(
        db,
      ).resolveCanonicalVariant(product: product, variantId: item.variantId);
      if (identity == null ||
          identity.supplierId != purchase.supplierId ||
          identity.productId != item.productId ||
          identity.canonicalVariantId != canonical) {
        throw const SupplierIdentityException(
          'supplier_purchase.source_mismatch',
        );
      }
    }
  }
}
