import 'dart:convert';
import 'package:crypto/crypto.dart';

class OfflineSyncException implements Exception {
  const OfflineSyncException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'OfflineSyncException($code): $message';
}

class SyncEventEnvelope {
  const SyncEventEnvelope({
    required this.eventId,
    required this.sourceDatabaseId,
    required this.organizationId,
    required this.branchId,
    required this.sequence,
    required this.eventType,
    required this.aggregateType,
    required this.aggregateId,
    required this.contractVersion,
    required this.payload,
    required this.occurredAt,
    required this.eventHash,
  });
  final String eventId;
  final String sourceDatabaseId;
  final String organizationId;
  final String branchId;
  final int sequence;
  final String eventType;
  final String aggregateType;
  final String aggregateId;
  final int contractVersion;
  final Map<String, Object?> payload;
  final DateTime occurredAt;
  final String eventHash;

  factory SyncEventEnvelope.fromJson(Map<String, Object?> json) {
    final rawPayload = json['payload'];
    if (rawPayload is! Map) {
      throw const OfflineSyncException(
        'invalid_event_payload',
        'The synchronization payload must be an object.',
      );
    }
    int readInt(String key) {
      final value = json[key];
      return value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return SyncEventEnvelope(
      eventId: json['eventId']?.toString() ?? '',
      sourceDatabaseId: json['sourceDatabaseId']?.toString() ?? '',
      organizationId: json['organizationId']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? '',
      sequence: readInt('sequence'),
      eventType: json['eventType']?.toString() ?? '',
      aggregateType: json['aggregateType']?.toString() ?? '',
      aggregateId: json['aggregateId']?.toString() ?? '',
      contractVersion: readInt('contractVersion'),
      payload: rawPayload.map(
        (key, value) => MapEntry(key.toString(), value as Object?),
      ),
      occurredAt: DateTime.parse(json['occurredAt']?.toString() ?? '').toUtc(),
      eventHash: json['eventHash']?.toString() ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'sourceDatabaseId': sourceDatabaseId,
    'organizationId': organizationId,
    'branchId': branchId,
    'sequence': sequence,
    'eventType': eventType,
    'aggregateType': aggregateType,
    'aggregateId': aggregateId,
    'contractVersion': contractVersion,
    'payload': payload,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'eventHash': eventHash,
  };
}

/// Stable wire contract shared by local ledgers and the online service.
class SyncWireContract {
  const SyncWireContract._();
  static const supportedContracts = {
    'catalogue.snapshot_page.v1',
    'customer.profile_upserted.v1',
    'customer_transaction.posted.v1',
    'customer_transaction.corrected.v1',
    'consignment_receipt.posted.v1',
    'consignment_receipt.voided.v1',
    'consignment_custody.posted.v1',
    'consignment_custody.voided.v1',
    'consignment_conversion.posted.v1',
    'consignment_conversion.voided.v1',
    'consignment_settlement.posted.v1',
    'consignment_settlement.voided.v1',
    'consignment_payment.posted.v1',
    'consignment_payment.reversed.v1',
    'location.snapshot_page.v1',
    'sale.posted.v1',
    'sale.voided.v1',
    'sale_return.posted.v1',
    'sale_return.voided.v1',
    'purchase.posted.v1',
    'purchase.voided.v1',
    'purchase_return.posted.v1',
    'purchase_return.voided.v1',
    'inventory_adjustment.posted.v1',
    'sale_adjustment_return.posted.v1',
    'sale_adjustment_return.voided.v1',
    'purchase_adjustment_return.posted.v1',
    'purchase_adjustment_return.voided.v1',
    'warehouse_transfer.dispatched.v1',
    'warehouse_transfer.received.v1',
    'warehouse_transfer.recalled.v1',
    'warehouse_transfer.recall_requested.v1',
    'warehouse_transfer.recall_resolved.v1',
  };
  static String eventHashFor(SyncEventEnvelope event) => sha256
      .convert(
        utf8.encode(
          jsonEncode(
            canonical({
              'eventId': event.eventId,
              'sourceDatabaseId': event.sourceDatabaseId,
              'organizationId': event.organizationId,
              'branchId': event.branchId,
              'sequence': event.sequence,
              'eventType': event.eventType,
              'aggregateType': event.aggregateType,
              'aggregateId': event.aggregateId,
              'contractVersion': event.contractVersion,
              'payload': event.payload,
              'occurredAt': event.occurredAt.toUtc().toIso8601String(),
            }),
          ),
        ),
      )
      .toString();

  static Object? canonical(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return <String, Object?>{
        for (final entry in entries)
          entry.key.toString(): canonical(entry.value),
      };
    }
    if (value is List) return value.map(canonical).toList(growable: false);
    return value;
  }

  static void validateJson(Object? value) {
    if (value == null || value is String || value is bool || value is int) {
      return;
    }
    if (value is double) {
      throw const OfflineSyncException(
        'floating_point_payload',
        'Use scaled integers for money, quantities, rates, and percentages.',
      );
    }
    if (value is List) {
      for (final item in value) {
        validateJson(item);
      }
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const OfflineSyncException(
            'non_json_payload',
            'Payload keys must be strings.',
          );
        }
        validateJson(entry.value);
      }
      return;
    }
    throw const OfflineSyncException(
      'non_json_payload',
      'Payload values must be JSON-compatible.',
    );
  }
}
