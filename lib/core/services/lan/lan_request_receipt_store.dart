import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'lan_business_models.dart';

final class LanLegacyRequestDocument {
  const LanLegacyRequestDocument({
    required this.id,
    required this.number,
    required this.totalCents,
  });

  final int id;
  final String number;
  final int totalCents;
}

final class LanRequestReservation {
  const LanRequestReservation._({required this.shouldCreate, this.documentId});

  const LanRequestReservation.create() : this._(shouldCreate: true);

  const LanRequestReservation.replay(int documentId)
    : this._(shouldCreate: false, documentId: documentId);

  final bool shouldCreate;
  final int? documentId;
}

/// Owns the durable identity of LAN mutations.
///
/// Call [reserve] and [complete] inside the same database transaction as the
/// business document. A failed document therefore rolls its reservation back,
/// while concurrent retries serialize on the composite primary key.
final class LanRequestReceiptStore {
  const LanRequestReceiptStore(this._db);

  final AppDatabase _db;

  String fingerprint(Map<String, dynamic> payload) {
    final withoutTransportIdentity = Map<String, dynamic>.from(payload)
      ..remove('idempotencyKey');
    return sha256
        .convert(utf8.encode(jsonEncode(_canonical(withoutTransportIdentity))))
        .toString();
  }

  Future<LanRequestReservation> reserve({
    required String operation,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
    required Future<LanLegacyRequestDocument?> Function() findLegacyDocument,
  }) async {
    final requestHash = fingerprint(payload);
    final rows = await _db
        .customSelect(
          '''SELECT request_hash, state, document_id
         FROM lan_request_receipts
         WHERE operation = ? AND idempotency_key = ?
         LIMIT 1''',
          variables: [Variable(operation), Variable(idempotencyKey)],
        )
        .get();
    if (rows.isNotEmpty) {
      final row = rows.single;
      final state = row.read<String>('state');
      final storedHash = row.readNullable<String>('request_hash');
      final documentId = row.readNullable<int>('document_id');
      if (state == 'legacy') {
        if (documentId == null) {
          throw const LanBusinessException(
            'idempotency_receipt_corrupt',
            'The saved request identity is incomplete.',
            statusCode: 409,
          );
        }
        return LanRequestReservation.replay(documentId);
      }
      if (storedHash != requestHash) {
        throw const LanBusinessException(
          'idempotency_payload_conflict',
          'This request identity was already used with different data.',
          statusCode: 409,
        );
      }
      if (state != 'completed' || documentId == null) {
        throw const LanBusinessException(
          'idempotency_request_in_progress',
          'This request is still being processed.',
          statusCode: 409,
        );
      }
      return LanRequestReservation.replay(documentId);
    }

    // Rows created before the request ledger already have unique idempotency
    // keys in their document tables. Preserve those documents as immutable
    // legacy receipts; their original transport payload cannot be recovered
    // reliably enough to manufacture a hash after the fact.
    final legacy = await findLegacyDocument();
    if (legacy != null) {
      await _db.customStatement(
        '''INSERT INTO lan_request_receipts (
             operation, idempotency_key, request_hash, state, document_id,
             document_number, total_cents, completed_at
           ) VALUES (?, ?, NULL, 'legacy', ?, ?, ?, CURRENT_TIMESTAMP)''',
        [
          operation,
          idempotencyKey,
          legacy.id,
          legacy.number,
          legacy.totalCents,
        ],
      );
      return LanRequestReservation.replay(legacy.id);
    }

    await _db.customStatement(
      '''INSERT INTO lan_request_receipts (
           operation, idempotency_key, request_hash, state
         ) VALUES (?, ?, ?, 'pending')''',
      [operation, idempotencyKey, requestHash],
    );
    return const LanRequestReservation.create();
  }

  Future<void> complete({
    required String operation,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
    required int documentId,
    required String documentNumber,
    required int totalCents,
  }) async {
    final changed = await _db.customUpdate(
      '''UPDATE lan_request_receipts
         SET state = 'completed', document_id = ?, document_number = ?,
             total_cents = ?, completed_at = CURRENT_TIMESTAMP
         WHERE operation = ? AND idempotency_key = ?
           AND request_hash = ? AND state = 'pending' ''',
      variables: [
        Variable(documentId),
        Variable(documentNumber),
        Variable(totalCents),
        Variable(operation),
        Variable(idempotencyKey),
        Variable(fingerprint(payload)),
      ],
      updates: const {},
    );
    if (changed != 1) {
      throw const LanBusinessException(
        'idempotency_receipt_corrupt',
        'The request result could not be saved safely.',
        statusCode: 409,
      );
    }
  }

  Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonical(value[key]),
      };
    }
    if (value is List) return value.map(_canonical).toList(growable: false);
    return value;
  }
}
