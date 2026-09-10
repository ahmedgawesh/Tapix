import 'package:easy_localization/easy_localization.dart';

typedef JournalEntryLabelResolver = String Function(String key);

String localizedJournalEntryType(
  String type, {
  JournalEntryLabelResolver? resolver,
}) => _localizedOrFallback(
  key: 'accounting.type_$type',
  fallback: type,
  resolver: resolver,
);

String localizedJournalSourceTable(
  String sourceTable, {
  JournalEntryLabelResolver? resolver,
}) => _localizedOrFallback(
  key: 'accounting.source_$sourceTable',
  fallback: sourceTable,
  resolver: resolver,
);

String _localizedOrFallback({
  required String key,
  required String fallback,
  JournalEntryLabelResolver? resolver,
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
