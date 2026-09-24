import 'dart:developer' as developer;

import '../../database/daos/settings_dao.dart';
import 'einvoice_artifact_repository.dart';
import 'einvoice_document.dart';
import 'einvoice_provider.dart';
import 'einvoice_provider_registry.dart';
import 'einvoice_status.dart';

/// **Single chokepoint** that dispatches every outgoing e-invoice.
///
/// The rule: nowhere else in the codebase does code write to
/// `einvoice_documents`, read the jurisdiction config, or talk to a
/// provider. Sales repositories and the return-posting service call
/// [dispatch] and walk away — everything else (chain context, state
/// machine, idempotency, persistence) is owned here.
///
/// Flow:
///   1. Read jurisdiction + enabled flag from `app_settings`.
///   2. Look up an existing artifact for (source_table, source_id).
///      If present and terminal → no-op.
///      If present and rejected → retry (attempt_count++).
///      If absent → insert a new `draft` row.
///   3. Compute the chain context (nextIcv + previousHash).
///   4. `provider.prepare()` → persist prepared fields.
///   5. `provider.sign()` → persist signed status.
///   6. `provider.submit()` → persist submission outcome.
///
/// Failures NEVER throw out to the caller: e-invoicing errors are a
/// downstream concern that must not roll back the accounting
/// transaction. The worst an integration bug can do is leave the row
/// in status=`rejected` with `last_error` set, which an operator can
/// retry from the UI.
class EInvoiceDispatchService {
  final EInvoiceProviderRegistry _registry;
  final EInvoiceArtifactRepository _repo;
  final SettingsDao _settings;

  EInvoiceDispatchService({
    required EInvoiceProviderRegistry registry,
    required EInvoiceArtifactRepository artifactRepository,
    required SettingsDao settingsDao,
  }) : _registry = registry,
       _repo = artifactRepository,
       _settings = settingsDao;

  static const String _keyJurisdiction = 'einvoice_jurisdiction';
  static const String _keyEnabled = 'einvoice_enabled';

  /// Dispatch the artifact for [subject]. Safe to call from any
  /// transactional code path: catches and logs all errors.
  ///
  /// Returns the final [EInvoiceStatus] (or `null` if dispatch was
  /// skipped because e-invoicing is disabled).
  Future<EInvoiceStatus?> dispatch(EInvoiceSubject subject) async {
    try {
      // ── 1. Jurisdiction config ──
      final enabled = (await _settings.getSetting(_keyEnabled)) == 'true';
      if (!enabled) {
        return null;
      }
      final jurisdiction = EInvoiceJurisdiction.fromWire(
        await _settings.getSetting(_keyJurisdiction),
      );
      if (jurisdiction == EInvoiceJurisdiction.none) {
        return null;
      }
      final provider = _registry.resolve(jurisdiction);

      // ── 2. Idempotency lookup ──
      final existing = await _repo.findBySource(
        sourceTable: subject.sourceTable,
        sourceId: subject.sourceId,
      );
      if (existing != null && existing.status.isTerminal) {
        return existing.status;
      }

      final int artifactId =
          existing?.id ??
          await _repo.insertDraft(
            sourceTable: subject.sourceTable,
            sourceId: subject.sourceId,
            jurisdiction: jurisdiction,
          );

      // ── 3. Chain context ──
      final head = await _repo.findChainHead(jurisdiction);
      final chain = EInvoiceChainContext(
        nextIcv: (head?.icv ?? 0) + 1,
        previousHash: head?.documentHash,
      );

      // ── 4. Prepare ──
      final prepared = await provider.prepare(subject, chain);
      await _repo.recordPrepared(
        id: artifactId,
        icv: prepared.icv,
        documentUuid: prepared.documentUuid,
        documentHash: prepared.documentHash,
        previousHash: prepared.previousHash,
        payloadXml: prepared.payloadXml,
        payloadJson: prepared.payloadJson,
        qrCodeBase64: prepared.qrCodeBase64,
      );

      // ── 5. Sign ──
      final signed = await provider.sign(prepared);
      await _repo.recordSigned(id: artifactId, signature: signed.signature);

      // ── 6. Submit ──
      final result = await provider.submit(prepared, signed);
      await _repo.recordSubmission(
        id: artifactId,
        status: result.status,
        responsePayload: result.responsePayload,
        lastError: result.lastError,
      );

      developer.log(
        'EInvoiceDispatch → ${subject.sourceTable}#${subject.sourceId} '
        'jurisdiction=${jurisdiction.wireValue} icv=${prepared.icv} '
        'status=${result.status.wireValue}',
        name: 'EInvoiceDispatch',
      );
      return result.status;
    } catch (e, st) {
      // Downstream failures must never break the accounting path.
      developer.log(
        'EInvoiceDispatch failed: $e\n$st',
        name: 'EInvoiceDispatch',
        error: e,
      );
      return EInvoiceStatus.rejected;
    }
  }
}
