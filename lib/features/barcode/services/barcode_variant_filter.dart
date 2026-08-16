/// Returns whether a database variant is a real label target.
///
/// Anonymous variants (no color and no size) are the internal backing row for
/// products without variants and must never be printed as an extra label.
bool shouldIncludeBarcodeVariant({
  required int variantId,
  required bool isActive,
  required bool hasDimensions,
  required Set<int> selectedVariantIds,
}) {
  return isActive &&
      hasDimensions &&
      (selectedVariantIds.isEmpty || selectedVariantIds.contains(variantId));
}
