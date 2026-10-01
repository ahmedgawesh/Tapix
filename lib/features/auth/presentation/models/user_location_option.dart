import '../../../../core/database/app_database.dart';

/// Presentation model for an operational location assigned to a user.
///
/// A branch sales floor and an independent warehouse are both stored in
/// [BusinessWarehouse] because both carry stock. Their operational meaning is
/// determined by `locationKind`, never by the legacy stored name.
class UserLocationOption {
  const UserLocationOption({required this.location, required this.branch});

  final BusinessWarehouse location;
  final BusinessBranch branch;

  bool get isBranchSalesFloor => location.locationKind == 'branch_store';

  String get primaryName {
    final candidate = isBranchSalesFloor ? branch.name : location.name;
    final trimmed = candidate.trim();
    return trimmed.isEmpty ? location.code : trimmed;
  }

  String label({
    required String salesFloorLabel,
    required String warehouseLabel,
  }) {
    final typeLabel = isBranchSalesFloor ? salesFloorLabel : warehouseLabel;
    return '$primaryName ($typeLabel) · ${location.code}';
  }

  static List<BusinessWarehouse> sortLocations(
    Iterable<BusinessWarehouse> locations,
  ) {
    final result = locations.toList(growable: false);
    result.sort((left, right) {
      final leftKind = left.locationKind == 'branch_store' ? 0 : 1;
      final rightKind = right.locationKind == 'branch_store' ? 0 : 1;
      final kindComparison = leftKind.compareTo(rightKind);
      if (kindComparison != 0) return kindComparison;

      final nameComparison = left.name.toLowerCase().compareTo(
        right.name.toLowerCase(),
      );
      if (nameComparison != 0) return nameComparison;
      return left.code.toLowerCase().compareTo(right.code.toLowerCase());
    });
    return result;
  }
}
