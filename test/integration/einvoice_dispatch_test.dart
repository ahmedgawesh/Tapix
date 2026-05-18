import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/settings_dao.dart';
import 'package:tapix/core/services/einvoice/einvoice_artifact_repository.dart';
import 'package:tapix/core/services/einvoice/einvoice_dispatch_service.dart';
import 'package:tapix/core/services/einvoice/einvoice_document.dart';
import 'package:tapix/core/services/einvoice/einvoice_provider_registry.dart';
import 'package:tapix/core/services/einvoice/einvoice_status.dart';
import 'package:tapix/core/services/einvoice/providers/null_einvoice_provider.dart';
import 'package:tapix/core/services/einvoice/providers/zatca_phase2_provider.dart';

/// Phase 4 — E-Invoicing dispatch integration tests.
///
/// Locks in the centralization contract:
///
/// 1. Registry hands back NullEInvoiceProvider when no provider is registered
///    for the configured jurisdiction.
/// 2. Dispatch is a no-op when e-invoicing is disabled in app_settings.
/// 3. Dispatch is a no-op when jurisdiction == NONE.
/// 4. Dispatch builds the artifact row, walks draft→prepared→signed→
///    (cleared/reported) and persists every transition.
/// 5. ICV chain is monotonic and PIH points to the previous artifact's hash.
/// 6. Idempotency: a second dispatch for the same (source_table, source_id)
///    after a terminal status is a silent no-op (no new row, no new ICV).
void main() {
  late AppDatabase db;
  late SettingsDao settingsDao;
  late EInvoiceArtifactRepository repo;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    settingsDao = SettingsDao(db);
    repo = EInvoiceArtifactRepository(db);
  });

  tearDown(() async => db.close());

  EInvoiceSubject subject({
    required int id,
    String table = 'sales',
    int total = 11500,
    int tax = 1500,
  }) =>
      EInvoiceSubject(
        sourceTable: table,
        sourceId: id,
        documentNumber: 'INV-$id',
        documentType: 'invoice',
        subtotalCents: total - tax,
        taxCents: tax,
        totalCents: total,
        currencyId: 1,
        issueDate: DateTime.utc(2026, 5, 11, 10),
        sellerTaxNumber: '300000000000003',
        sellerLegalName: 'Tapix Test Co.',
        lines: const [],
      );

  group('Registry resolution', () {
    test('returns NullEInvoiceProvider for unconfigured jurisdictions', () {
      final reg = EInvoiceProviderRegistry();
      expect(reg.resolve(EInvoiceJurisdiction.none), isA<NullEInvoiceProvider>());
      expect(reg.resolve(EInvoiceJurisdiction.ksaZatcaPhase2),
          isA<NullEInvoiceProvider>());
      expect(reg.hasProvider(EInvoiceJurisdiction.ksaZatcaPhase2), isFalse);
    });

    test('returns the matching provider when registered', () {
      const zatca = ZatcaPhase2Provider(
        sellerTaxNumber: '300000000000003',
        sellerLegalName: 'Tapix Test Co.',
      );
      final reg = EInvoiceProviderRegistry(providers: const [zatca]);
      expect(reg.resolve(EInvoiceJurisdiction.ksaZatcaPhase2), same(zatca));
      expect(reg.hasProvider(EInvoiceJurisdiction.ksaZatcaPhase2), isTrue);
      expect(reg.hasProvider(EInvoiceJurisdiction.egEta), isFalse);
    });
  });

  group('Dispatcher no-op semantics', () {
    test('returns null when e-invoicing is disabled', () async {
      final svc = EInvoiceDispatchService(
        registry: EInvoiceProviderRegistry(),
        artifactRepository: repo,
        settingsDao: settingsDao,
      );
      // einvoice_enabled is unset → treated as disabled.
      final s = await svc.dispatch(subject(id: 1));
      expect(s, isNull);
      final row = await repo.findBySource(sourceTable: 'sales', sourceId: 1);
      expect(row, isNull, reason: 'no artifact row when disabled');
    });

    test('returns null when jurisdiction == NONE', () async {
      await settingsDao.saveSetting('einvoice_enabled', 'true');
      await settingsDao.saveSetting('einvoice_jurisdiction', 'NONE');
      final svc = EInvoiceDispatchService(
        registry: EInvoiceProviderRegistry(),
        artifactRepository: repo,
        settingsDao: settingsDao,
      );
      expect(await svc.dispatch(subject(id: 2)), isNull);
    });
  });

  group('ZATCA Phase 2 happy path (offline mode)', () {
    late EInvoiceDispatchService svc;

    setUp(() async {
      await settingsDao.saveSetting('einvoice_enabled', 'true');
      await settingsDao.saveSetting(
          'einvoice_jurisdiction', 'KSA_ZATCA_PHASE2');
      const zatca = ZatcaPhase2Provider(
        sellerTaxNumber: '300000000000003',
        sellerLegalName: 'Tapix Test Co.',
      );
      svc = EInvoiceDispatchService(
        registry: EInvoiceProviderRegistry(providers: const [zatca]),
        artifactRepository: repo,
        settingsDao: settingsDao,
      );
    });

    test('first dispatch produces ICV=1, no previousHash, terminal status',
        () async {
      final status = await svc.dispatch(subject(id: 10));
      expect(status, anyOf(EInvoiceStatus.reported, EInvoiceStatus.cleared));

      final row = await repo.findBySource(sourceTable: 'sales', sourceId: 10);
      expect(row, isNotNull);
      expect(row!.icv, 1);
      expect(row.previousHash, isNull);
      expect(row.documentUuid, isNotNull);
      expect(row.documentHash, isNotNull);
      expect(row.status.isTerminal, isTrue);
      expect(row.attemptCount, greaterThanOrEqualTo(1));
    });

    test('second dispatch chains ICV=2 and previousHash matches first hash',
        () async {
      await svc.dispatch(subject(id: 20));
      final first =
          await repo.findBySource(sourceTable: 'sales', sourceId: 20);
      expect(first!.icv, 1);

      await svc.dispatch(subject(id: 21));
      final second =
          await repo.findBySource(sourceTable: 'sales', sourceId: 21);
      expect(second!.icv, 2);
      expect(second.previousHash, first.documentHash);
      expect(second.documentHash, isNot(first.documentHash));
    });

    test('idempotency: re-dispatching a terminal artifact is a no-op',
        () async {
      await svc.dispatch(subject(id: 30));
      final first =
          await repo.findBySource(sourceTable: 'sales', sourceId: 30);
      expect(first!.status.isTerminal, isTrue);
      final attemptsBefore = first.attemptCount;

      // Second call must NOT advance the chain, NOT bump attempts.
      final s = await svc.dispatch(subject(id: 30));
      expect(s, first.status);

      final again =
          await repo.findBySource(sourceTable: 'sales', sourceId: 30);
      expect(again!.icv, first.icv);
      expect(again.documentHash, first.documentHash);
      expect(again.attemptCount, attemptsBefore);

      // And the chain head must not have advanced.
      final head =
          await repo.findChainHead(EInvoiceJurisdiction.ksaZatcaPhase2);
      expect(head!.icv, first.icv);
    });

    test('credit notes for sale_returns are persisted with their own row',
        () async {
      await svc.dispatch(subject(id: 40, table: 'sales'));
      final cn = EInvoiceSubject(
        sourceTable: 'sale_returns',
        sourceId: 40,
        documentNumber: 'CN-40',
        documentType: 'credit_note',
        subtotalCents: 1000,
        taxCents: 150,
        totalCents: 1150,
        currencyId: 1,
        issueDate: DateTime.utc(2026, 5, 12),
        sellerTaxNumber: '300000000000003',
        sellerLegalName: 'Tapix Test Co.',
        lines: const [],
        originalInvoiceNumber: 'INV-40',
      );
      await svc.dispatch(cn);

      final invoiceRow =
          await repo.findBySource(sourceTable: 'sales', sourceId: 40);
      final creditRow =
          await repo.findBySource(sourceTable: 'sale_returns', sourceId: 40);
      expect(invoiceRow, isNotNull);
      expect(creditRow, isNotNull);
      // Same source_id but different source_table → both rows coexist
      // (unique key is the composite, not source_id alone).
      expect(creditRow!.icv, invoiceRow!.icv! + 1);
      expect(creditRow.previousHash, invoiceRow.documentHash);
    });
  });
}
