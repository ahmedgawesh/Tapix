import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import 'supplier_identity_rules.dart';

/// Read-only preview. A UI build or a change of supplier must never issue a code.
class SupplierIdentityPreview {
  const SupplierIdentityPreview({
    required this.supplierId,
    required this.productId,
    required this.canonicalVariantId,
    required this.supplierCode,
    required this.baseSku,
    required this.sourceSku,
    this.identityId,
  });

  final int supplierId;
  final int productId;
  final int canonicalVariantId;
  final String supplierCode;
  final String baseSku;
  final String sourceSku;
  final int? identityId;
  bool get alreadyIssued => identityId != null;
}

class SupplierIdentitySelection {
  const SupplierIdentitySelection({
    required this.identityId,
    required this.supplierId,
    required this.supplierName,
    required this.productId,
    required this.canonicalVariantId,
    required this.sourceSku,
  });

  final int identityId;
  final int supplierId;
  final String supplierName;
  final int productId;
  final int canonicalVariantId;
  final String sourceSku;
}

/// Foundation for source-specific SKUs. This service owns NO stock balance.
///
/// Purchase posting issues identities, while sales and standalone customer
/// returns may preserve an explicitly selected identity. Legacy rows remain
/// unassigned and a preferred supplier is never treated as source evidence.
class SupplierProductIdentityService {
  SupplierProductIdentityService(this.db);

  final AppDatabase db;

  Future<SupplierProductIdentity?> getById(int identityId) => (db.select(
    db.supplierProductIdentities,
  )..where((i) => i.id.equals(identityId))).getSingleOrNull();

  Future<SupplierIdentitySelection?> getSelectionById(int identityId) async {
    final row = await db
        .customSelect(
          '''SELECT i.id,i.supplier_id,s.name AS supplier_name,i.product_id,
      i.canonical_variant_id,i.source_sku
      FROM supplier_product_identities i
      JOIN suppliers s ON s.id=i.supplier_id
      WHERE i.id=?''',
          variables: [Variable.withInt(identityId)],
          readsFrom: {db.supplierProductIdentities, db.suppliers},
        )
        .getSingleOrNull();
    return row == null ? null : _selection(row);
  }

  Future<List<SupplierIdentitySelection>> getProductSelections(
    int productId, {
    int? variantId,
  }) async {
    final rows = await db
        .customSelect(
          '''SELECT i.id,i.supplier_id,s.name AS supplier_name,i.product_id,
      i.canonical_variant_id,i.source_sku
      FROM supplier_product_identities i
      JOIN suppliers s ON s.id=i.supplier_id
      WHERE i.product_id=? AND (? IS NULL OR i.canonical_variant_id=?)
        AND s.is_active=1
      ORDER BY s.name COLLATE NOCASE,i.source_sku COLLATE NOCASE''',
          variables: [
            Variable.withInt(productId),
            Variable<int>(variantId),
            Variable<int>(variantId),
          ],
          readsFrom: {db.supplierProductIdentities, db.suppliers},
        )
        .get();
    return rows.map(_selection).toList(growable: false);
  }

  Future<SupplierIdentitySelection?> resolveSelection(String input) async {
    final identity = await resolveSourceSku(input);
    return identity == null ? null : getSelectionById(identity.id);
  }

  Future<SupplierIdentitySelection> requireForLine({
    required int identityId,
    required int productId,
    int? variantId,
  }) async {
    final selection = await getSelectionById(identityId);
    if (selection == null ||
        selection.productId != productId ||
        (variantId != null && selection.canonicalVariantId != variantId)) {
      throw const SupplierIdentityException(
        'supplier_identity.source_mismatch',
      );
    }
    if (variantId == null) {
      final product = await (db.select(
        db.products,
      )..where((p) => p.id.equals(productId))).getSingleOrNull();
      if (product == null || product.hasVariants || !product.trackInventory) {
        throw const SupplierIdentityException(
          'supplier_identity.source_mismatch',
        );
      }
    }
    return selection;
  }

  SupplierIdentitySelection _selection(QueryRow row) =>
      SupplierIdentitySelection(
        identityId: row.read<int>('id'),
        supplierId: row.read<int>('supplier_id'),
        supplierName: row.read<String>('supplier_name'),
        productId: row.read<int>('product_id'),
        canonicalVariantId: row.read<int>('canonical_variant_id'),
        sourceSku: row.read<String>('source_sku'),
      );

  /// Historical reads work after a supplier is inactive and after a setting
  /// has been switched off. Ownership is never inferred from a prefix string.
  Future<SupplierProductIdentity?> resolveSourceSku(String input) async {
    final code = input.trim();
    if (code.isEmpty) return null;
    final row = await db
        .customSelect(
          'SELECT id FROM supplier_product_identities '
          'WHERE source_sku = ? COLLATE NOCASE',
          variables: [Variable.withString(code)],
          readsFrom: {db.supplierProductIdentities},
        )
        .getSingleOrNull();
    if (row == null) return null;
    return getById(row.read<int>('id'));
  }

  Future<SupplierProductIdentity?> findForVariant({
    required int supplierId,
    required int canonicalVariantId,
  }) =>
      (db.select(db.supplierProductIdentities)..where(
            (i) =>
                i.supplierId.equals(supplierId) &
                i.canonicalVariantId.equals(canonicalVariantId),
          ))
          .getSingleOrNull();

  Future<List<SupplierProductIdentity>> getProductIdentities(int productId) =>
      (db.select(db.supplierProductIdentities)
            ..where((i) => i.productId.equals(productId))
            ..orderBy([(i) => OrderingTerm.asc(i.sourceSku)]))
          .get();

  Future<int> resolveCanonicalVariant({
    required Product product,
    int? variantId,
  }) async {
    if (!product.hasVariants) {
      final candidates =
          await (db.select(db.productVariants)
                ..where(
                  (v) =>
                      v.productId.equals(product.id) & v.isActive.equals(true),
                )
                ..limit(2))
              .get();
      if (candidates.length != 1 ||
          (variantId != null && candidates.single.id != variantId)) {
        throw const SupplierIdentityException(
          'supplier_identity.variant_required',
        );
      }
      return candidates.single.id;
    }
    if (variantId == null || variantId <= 0) {
      throw const SupplierIdentityException(
        'supplier_identity.variant_required',
      );
    }
    final variant =
        await (db.select(db.productVariants)..where(
              (v) =>
                  v.id.equals(variantId) &
                  v.productId.equals(product.id) &
                  v.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (variant == null) {
      throw const SupplierIdentityException(
        'supplier_identity.source_mismatch',
      );
    }
    return variant.id;
  }

  Future<SupplierIdentityPreview> preview({
    required int supplierId,
    required int productId,
    int? variantId,
  }) async {
    final supplier = await (db.select(
      db.suppliers,
    )..where((s) => s.id.equals(supplierId))).getSingleOrNull();
    final product = await (db.select(
      db.products,
    )..where((p) => p.id.equals(productId))).getSingleOrNull();
    if (supplier == null || product == null) {
      throw const SupplierIdentityException(
        'supplier_identity.source_mismatch',
      );
    }
    if (!supplier.isActive || !product.isActive) {
      throw const SupplierIdentityException(
        'supplier_identity.inactive_source',
      );
    }
    final canonical = await resolveCanonicalVariant(
      product: product,
      variantId: variantId,
    );
    final existing = await findForVariant(
      supplierId: supplierId,
      canonicalVariantId: canonical,
    );
    if (existing != null) {
      if (existing.productId != productId) {
        throw const SupplierIdentityException(
          'supplier_identity.source_mismatch',
        );
      }
      return SupplierIdentityPreview(
        supplierId: existing.supplierId,
        productId: existing.productId,
        canonicalVariantId: existing.canonicalVariantId,
        supplierCode: existing.supplierCodeSnapshot,
        baseSku: existing.baseSkuSnapshot,
        sourceSku: existing.sourceSku,
        identityId: existing.id,
      );
    }
    final supplierCode = SupplierIdentityRules.requireSupplierCode(
      supplier.productCode,
    );
    final variant = await (db.select(
      db.productVariants,
    )..where((v) => v.id.equals(canonical))).getSingle();
    // A multi-variant item needs its own base SKU; using the parent's would
    // make two sizes scan as one. Simple items keep the user's parent SKU.
    final baseSku = SupplierIdentityRules.validateBaseSku(
      product.hasVariants ? variant.sku : product.sku,
    );
    final sourceSku = SupplierIdentityRules.composeSourceSku(
      supplierCode: supplierCode,
      baseSku: baseSku,
    );
    await _assertNamespaceAvailable(sourceSku);
    return SupplierIdentityPreview(
      supplierId: supplierId,
      productId: productId,
      canonicalVariantId: canonical,
      supplierCode: supplierCode,
      baseSku: baseSku,
      sourceSku: sourceSku,
    );
  }

  /// Call from the SAME database transaction as a future approved receipt or
  /// explicit issuance operation. Do not call while rendering a form/preview.
  /// The pair lookup, unique index, and no-replace trigger make retries stable.
  Future<SupplierProductIdentity> ensureIssued({
    required int supplierId,
    required int productId,
    int? variantId,
  }) => db.transaction(() async {
    final mode = await db.settingsDao.getSetting('lan.mode');
    if (mode == 'client') {
      throw const SupplierIdentityException(
        'supplier_identity.master_required',
      );
    }
    final candidate = await preview(
      supplierId: supplierId,
      productId: productId,
      variantId: variantId,
    );
    if (candidate.identityId != null) {
      return (await getById(candidate.identityId!))!;
    }
    try {
      final id = await db
          .into(db.supplierProductIdentities)
          .insert(
            SupplierProductIdentitiesCompanion.insert(
              supplierId: supplierId,
              productId: productId,
              canonicalVariantId: candidate.canonicalVariantId,
              supplierCodeSnapshot: candidate.supplierCode,
              baseSkuSnapshot: candidate.baseSku,
              sourceSku: candidate.sourceSku,
            ),
          );
      return (await getById(id))!;
    } catch (error) {
      final failure = SupplierIdentityException.fromError(error);
      if (failure?.messageKey == 'supplier_identity.identity_exists') {
        // Only the SAME pair may win an insert race. Never reuse a code
        // belonging to a different supplier or variant.
        final winner = await findForVariant(
          supplierId: supplierId,
          canonicalVariantId: candidate.canonicalVariantId,
        );
        if (winner != null && winner.productId == productId) return winner;
        throw const SupplierIdentityException(
          'supplier_identity.source_code_collision',
        );
      }
      if (failure != null) throw failure;
      rethrow;
    }
  });

  Future<void> _assertNamespaceAvailable(String code) async {
    final match = await db.customSelect(
      '''SELECT 1 AS found WHERE
      EXISTS(SELECT 1 FROM products WHERE trim(sku)=? COLLATE NOCASE OR trim(barcode)=? COLLATE NOCASE)
      OR EXISTS(SELECT 1 FROM product_variants WHERE trim(sku)=? COLLATE NOCASE OR trim(barcode)=? COLLATE NOCASE)
      OR EXISTS(SELECT 1 FROM supplier_product_identities WHERE source_sku=? COLLATE NOCASE)''',
      variables: List.generate(5, (_) => Variable.withString(code)),
    ).getSingleOrNull();
    if (match != null) {
      throw const SupplierIdentityException(
        'supplier_identity.source_code_collision',
      );
    }
  }
}
