/// Shared, locale-independent validation for supplier product identities.
///
/// Supplier prefixes are identifiers, never numbers: "007" stays "007".
/// This file intentionally has no Flutter, database, or network dependency.
class SupplierIdentityException implements Exception {
  const SupplierIdentityException(this.messageKey);

  final String messageKey;

  @override
  String toString() => messageKey;

  /// Translate only our own constraint failures, not unrelated SQL errors.
  static SupplierIdentityException? fromError(Object error) {
    if (error is SupplierIdentityException) return error;
    final text = error.toString();
    for (final key in const [
      'supplier_purchase.source_mismatch',
      'supplier_purchase.history_locked',
      'supplier_identity.invalid_code',
      'supplier_identity.code_in_use',
      'supplier_identity.code_locked',
      'supplier_identity.delete_blocked',
      'supplier_identity.identity_exists',
      'supplier_identity.identity_immutable',
      'supplier_identity.source_mismatch',
      'supplier_identity.source_code_collision',
      'supplier_identity.base_sku_required',
      'supplier_identity.base_sku_invalid',
      'supplier_identity.inactive_source',
      'supplier_identity.insufficient_source_quantity',
      'supplier_identity.master_required',
    ]) {
      if (text.contains(key)) return SupplierIdentityException(key);
    }
    // Fallbacks for unique constraints when SQLite wins an insert race.
    if (text.contains('UNIQUE constraint failed: suppliers.product_code') ||
        text.contains('idx_suppliers_product_code_unique')) {
      return const SupplierIdentityException('supplier_identity.code_in_use');
    }
    if (text.contains(
          'UNIQUE constraint failed: supplier_product_identities.',
        ) ||
        text.contains('idx_supplier_identity_source_sku')) {
      return const SupplierIdentityException(
        'supplier_identity.identity_exists',
      );
    }
    return null;
  }
}

class SupplierIdentityRules {
  SupplierIdentityRules._();

  static const maxSupplierCodeLength = 12;
  static const maxBaseSkuLength = 64;
  static final _supplierPattern = RegExp(r'^[A-Z0-9]{1,12}$');
  static final _basePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/\-]{0,63}$');
  static final _legacyReceiptPattern = RegExp(r'^TR-[0-9A-F]{32}$');

  /// Blank codes are stored as NULL, so many legacy suppliers can omit them.
  /// Trim outer whitespace only; do not silently strip invalid characters.
  static String? normalizeSupplierCode(String? input) {
    if (input == null) return null;
    final value = input.trim();
    if (value.isEmpty) return null;
    // Validate the original ASCII alphabet before uppercasing. Some non-ASCII
    // characters uppercase to ASCII and must not become hidden aliases.
    if (!RegExp(r'^[A-Za-z0-9]{1,12}$').hasMatch(value)) {
      throw const SupplierIdentityException('supplier_identity.invalid_code');
    }
    return value.toUpperCase();
  }

  static bool isNormalizedSupplierCode(String value) =>
      _supplierPattern.hasMatch(value);

  static String requireSupplierCode(String? input) {
    final code = normalizeSupplierCode(input);
    if (code == null) {
      throw const SupplierIdentityException('supplier_identity.code_required');
    }
    return code;
  }

  static String validateBaseSku(String? input) {
    final value = input?.trim();
    if (value == null || value.isEmpty) {
      throw const SupplierIdentityException(
        'supplier_identity.base_sku_required',
      );
    }
    if (!_basePattern.hasMatch(value)) {
      throw const SupplierIdentityException(
        'supplier_identity.base_sku_invalid',
      );
    }
    return value;
  }

  /// This is only called for a NEW relationship. Existing source SKUs are
  /// looked up by supplier + canonical variant, never parsed or concatenated.
  static String composeSourceSku({
    required String supplierCode,
    required String baseSku,
  }) {
    final code = requireSupplierCode(supplierCode);
    final base = validateBaseSku(baseSku);
    final source = '$code-$base';
    if (_legacyReceiptPattern.hasMatch(source.toUpperCase())) {
      throw const SupplierIdentityException(
        'supplier_identity.source_code_collision',
      );
    }
    return source;
  }
}
