import 'package:easy_localization/easy_localization.dart';

typedef AuditLabelResolver = String Function(String key);

String localizedAuditEntityType(
  String entityType, {
  AuditLabelResolver? resolver,
}) => _localizedOrFallback(
  key: 'audit.entity_$entityType',
  fallback: entityType,
  resolver: resolver,
);

String localizedAuditAction(String action, {AuditLabelResolver? resolver}) =>
    _localizedOrFallback(
      key: 'audit.action_$action',
      fallback: action,
      resolver: resolver,
    );

String localizedAuditChangeKey(String key, {AuditLabelResolver? resolver}) =>
    _localizedOrFallback(
      key: 'audit.change_$key',
      fallback: key,
      resolver: resolver,
    );

String localizedAuditChangeValue(
  String parentKey,
  Object? value, {
  AuditLabelResolver? resolver,
}) {
  final resolve = resolver ?? (key) => key.tr();
  if (value == null) return resolve('audit.value_null');
  if (value is bool) {
    return resolve(value ? 'audit.value_true' : 'audit.value_false');
  }
  if (parentKey == 'status' || parentKey == 'severity') {
    final raw = value.toString();
    final key = 'audit.value_$raw';
    final translated = resolve(key);
    if (translated != key) return translated;
  }
  return value.toString();
}

String formatLocalizedAuditChanges(
  Map<String, dynamic> changes, {
  AuditLabelResolver? resolver,
}) {
  final resolve = resolver ?? (key) => key.tr();
  if (changes.isEmpty) return resolve('audit.value_empty');
  final buffer = StringBuffer();
  for (final entry in changes.entries) {
    final label = localizedAuditChangeKey(entry.key, resolver: resolve);
    if (entry.value is Map) {
      buffer.writeln('$label:');
      for (final sub in (entry.value as Map).entries) {
        final subKey = sub.key.toString();
        final subLabel = localizedAuditChangeKey(subKey, resolver: resolve);
        final value = localizedAuditChangeValue(
          subKey,
          sub.value,
          resolver: resolve,
        );
        buffer.writeln('  $subLabel: $value');
      }
    } else {
      final value = localizedAuditChangeValue(
        entry.key,
        entry.value,
        resolver: resolve,
      );
      buffer.writeln('$label: $value');
    }
  }
  return buffer.toString().trimRight();
}

String _localizedOrFallback({
  required String key,
  required String fallback,
  AuditLabelResolver? resolver,
}) {
  final resolve = resolver ?? (value) => value.tr();
  final translated = resolve(key);
  return translated == key ? _humanize(fallback) : translated;
}

String _humanize(String value) {
  final words = value.replaceAll('_', ' ').trim();
  if (words.isEmpty) return value;
  return '${words[0].toUpperCase()}${words.substring(1)}';
}
