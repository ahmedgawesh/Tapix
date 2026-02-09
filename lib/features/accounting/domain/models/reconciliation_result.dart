/// Result of reconciliation check
class ReconciliationResult {
  final bool isHealthy;
  final List<String> issues;
  final DateTime timestamp;

  ReconciliationResult({
    required this.isHealthy,
    required this.issues,
    required this.timestamp,
  });
}
