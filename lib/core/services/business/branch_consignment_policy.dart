/// Durable branch switch for the optional consignment module included in Pro.
///
/// This policy only opens the module. It never changes ownership, valuation,
/// supplier liabilities, or existing documents by itself.
class BranchConsignmentPolicy {
  const BranchConsignmentPolicy({required this.enabled});

  final bool enabled;

  Map<String, Object> toJson() => {'enabled': enabled};

  factory BranchConsignmentPolicy.fromJson(Object? input) {
    if (input is! Map || input['enabled'] is! bool) {
      throw const FormatException('Invalid branch consignment policy.');
    }
    return BranchConsignmentPolicy(enabled: input['enabled'] as bool);
  }
}
