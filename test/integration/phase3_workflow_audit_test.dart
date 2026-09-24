import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/database/daos/settings_dao.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/returns/return_approval_decision.dart';
import 'package:tapix/core/services/returns/return_approval_exceptions.dart';
import 'package:tapix/core/services/returns/return_approval_service.dart';
import 'package:tapix/core/services/returns/return_journal_policy.dart';
import 'package:tapix/core/services/returns/return_posting_service.dart';
import 'package:tapix/core/services/returns/return_reason_code_service.dart';
import 'package:tapix/core/services/compliance/customer_credit_note_service.dart';
import 'package:tapix/core/services/compliance/fiscal_period_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

/// Phase 3 — Workflow & Audit regression suite.
///
/// Locks the centralisation contract:
///
///   * Approval **policy** lives in exactly one class (`ReturnApprovalService`)
///     and is consumed by both the DAO at draft creation and the UI manager
///     screen — there is no scattered policy code.
///   * Approval **enforcement** lives in exactly one chokepoint
///     (`ReturnPostingService.post`) which inspects the persisted
///     `approval_status` and refuses to post anything not in
///     `ApprovalStatus.postable`.
///   * Audit columns (`posted_by`, `posted_at`, `voided_by`, `voided_at`,
///     `void_reason`) are written by the DAO post/void paths and never by
///     ad-hoc UI code.
///   * `return_reason_codes` is the single normalised lookup table — system
///     rows are protected from rename/delete via
///     `SystemReasonCodeProtectedException`.
void main() {
  late AppDatabase db;
  late SettingsDao settingsDao;
  late AdjustmentReturnDao adjDao;
  late AccountingRepository accountingRepo;
  late ReturnJournalPolicy policy;
  late ReturnPostingService postingService;
  late FiscalPeriodService fiscalService;
  late CustomerCreditNoteService creditNoteService;
  late JournalEntryService journalService;
  late ReturnApprovalService approvalService;
  late ReturnReasonCodeService reasonCodeService;

  late int currencyId;
  late int productId;
  late int variantId;
  late int customerId;
  late int supplierId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    settingsDao = SettingsDao(db);
    accountingRepo = AccountingRepository(db);
    policy = ReturnJournalPolicy(accountingRepo);
    fiscalService = FiscalPeriodService(db);
    creditNoteService = CustomerCreditNoteService(
      db: db,
      accountingRepo: accountingRepo,
    );
    postingService = ReturnPostingService(
      accountingRepo: accountingRepo,
      policy: policy,
      fiscalPeriodService: fiscalService,
      creditNoteService: creditNoteService,
    );
    journalService = JournalEntryService(
      accountingRepo,
      returnPostingService: postingService,
    );
    adjDao = AdjustmentReturnDao(db);
    approvalService = ReturnApprovalService(settingsDao);
    reasonCodeService = ReturnReasonCodeService(db);

    // Trigger migrations + seed.
    await db.customSelect('SELECT 1').get();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users (id, username, password_hash, role, '
      'is_active, created_at, updated_at) '
      "VALUES (0, 'system', 'no-pin', 'owner', 1, $now, $now)",
    );
    await db.customStatement(
      'INSERT OR IGNORE INTO users (id, username, password_hash, role, '
      'is_active, created_at, updated_at) '
      "VALUES (7, 'manager', 'no-pin', 'owner', 1, $now, $now)",
    );

    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    currencyId = usd.id;

    productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            sku: const Value<String?>('P3-TEST-001'),
            name: 'Phase 3 Product',
            costCents: Decimal.fromInt(3000),
            priceCents: Decimal.fromInt(5000),
            currencyId: Value(currencyId),
            stockQuantity: const Value(100),
          ),
        );
    variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(100),
            costCents: Decimal.fromInt(3000),
            priceCents: Decimal.fromInt(5000),
          ),
        );
    customerId = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            name: 'P3 Customer',
            currencyId: currencyId,
            balanceCents: Value(Decimal.fromInt(100000)),
          ),
        );
    supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'P3 Supplier',
            currencyId: currencyId,
            balanceCents: Value(Decimal.fromInt(100000)),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  // ──────────────────────────────────────────────────────────────────────
  // 1. Policy evaluation — pure, stateless, single source of truth
  // ──────────────────────────────────────────────────────────────────────
  group('Phase 3.4 — ReturnApprovalService.evaluate (policy)', () {
    test('all rules off → autoApproved regardless of inputs', () async {
      await approvalService.setThresholdCents(0);
      await approvalService.setRequireWhenNoInvoice(false);
      await approvalService.setRequireOnOverride(false);

      final d = await approvalService.evaluate(
        const ReturnApprovalContext(
          totalCents: 999999,
          linked: false,
          overHistoryOverride: true,
          side: 'sale',
        ),
      );
      expect(d.outcome, ReturnApprovalOutcome.autoApproved);
      expect(d.reasonCodes, isEmpty);
      expect(d.persistedStatus, ApprovalStatus.autoApproved);
    });

    test('threshold rule fires when totalCents >= threshold', () async {
      await approvalService.setThresholdCents(10000);
      await approvalService.setRequireWhenNoInvoice(false);
      await approvalService.setRequireOnOverride(false);

      final hit = await approvalService.evaluate(
        const ReturnApprovalContext(
          totalCents: 10000,
          linked: true,
          overHistoryOverride: false,
          side: 'sale',
        ),
      );
      expect(hit.outcome, ReturnApprovalOutcome.requiresApproval);
      expect(hit.reasonCodes, contains(ApprovalReasonCode.thresholdExceeded));
      expect(hit.thresholdCents, 10000);
      expect(hit.persistedStatus, ApprovalStatus.pending);

      final miss = await approvalService.evaluate(
        const ReturnApprovalContext(
          totalCents: 9999,
          linked: true,
          overHistoryOverride: false,
          side: 'sale',
        ),
      );
      expect(miss.outcome, ReturnApprovalOutcome.autoApproved);
    });

    test('no-invoice rule fires only on unlinked returns', () async {
      await approvalService.setThresholdCents(0);
      await approvalService.setRequireWhenNoInvoice(true);
      await approvalService.setRequireOnOverride(false);

      final adj = await approvalService.evaluate(
        const ReturnApprovalContext(
          totalCents: 100,
          linked: false,
          overHistoryOverride: false,
          side: 'sale',
        ),
      );
      expect(adj.reasonCodes, contains(ApprovalReasonCode.noInvoice));

      final linked = await approvalService.evaluate(
        const ReturnApprovalContext(
          totalCents: 100,
          linked: true,
          overHistoryOverride: false,
          side: 'sale',
        ),
      );
      expect(linked.outcome, ReturnApprovalOutcome.autoApproved);
    });

    test('override rule fires only when overHistoryOverride=true', () async {
      await approvalService.setThresholdCents(0);
      await approvalService.setRequireWhenNoInvoice(false);
      await approvalService.setRequireOnOverride(true);

      final fired = await approvalService.evaluate(
        const ReturnApprovalContext(
          totalCents: 100,
          linked: true,
          overHistoryOverride: true,
          side: 'purchase',
        ),
      );
      expect(fired.reasonCodes, contains(ApprovalReasonCode.overrideUsed));
    });

    test(
      'multiple rules accumulate reason codes (additive precedence)',
      () async {
        await approvalService.setThresholdCents(5000);
        await approvalService.setRequireWhenNoInvoice(true);
        await approvalService.setRequireOnOverride(true);

        final d = await approvalService.evaluate(
          const ReturnApprovalContext(
            totalCents: 10000,
            linked: false,
            overHistoryOverride: true,
            side: 'sale',
          ),
        );
        expect(d.outcome, ReturnApprovalOutcome.requiresApproval);
        expect(
          d.reasonCodes,
          containsAll(<String>[
            ApprovalReasonCode.thresholdExceeded,
            ApprovalReasonCode.noInvoice,
            ApprovalReasonCode.overrideUsed,
          ]),
        );
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────
  // 2. DAO persists policy decision atomically with draft creation
  // ──────────────────────────────────────────────────────────────────────
  group('Phase 3.5 — DAO persists approval decision on draft creation', () {
    test(
      'draft above threshold lands as pending with persisted reason',
      () async {
        await approvalService.setThresholdCents(4000);
        await approvalService.setRequireWhenNoInvoice(false);
        await approvalService.setRequireOnOverride(false);

        final returnId = await adjDao.createSaleAdjReturn(
          SaleReturnAdjustmentsCompanion.insert(
            returnNumber: 'SAR-P3-001',
            customerId: Value(customerId),
            currencyId: currencyId,
            totalCents: Decimal.fromInt(5000),
            refundMethod: const Value('cash'),
          ),
          [
            SaleReturnAdjustmentItemsCompanion.insert(
              sourceResolution: const Value('unverified'),
              sourceResolutionReason: const Value('test fixture'),
              returnId: 0,
              productId: productId,
              variantId: Value(variantId),
              quantity: 1,
              unitPriceCents: Decimal.fromInt(5000),
              totalCents: Decimal.fromInt(5000),
            ),
          ],
          approvalService: approvalService,
        );

        final row = await adjDao.getSaleAdjReturnById(returnId);
        expect(row, isNotNull);
        expect(row!.approvalStatus, ApprovalStatus.pending);
        expect(row.approvalRequired, isTrue);
        expect(
          row.approvalReason,
          contains(ApprovalReasonCode.thresholdExceeded),
        );
      },
    );

    test('draft below all rules lands as auto_approved', () async {
      await approvalService.setThresholdCents(100000);
      await approvalService.setRequireWhenNoInvoice(false);
      await approvalService.setRequireOnOverride(false);

      final returnId = await adjDao.createPurchaseAdjReturn(
        PurchaseReturnAdjustmentsCompanion.insert(
          returnNumber: 'PAR-P3-001',
          supplierId: supplierId,
          currencyId: currencyId,
          totalCents: Decimal.fromInt(100),
        ),
        [
          PurchaseReturnAdjustmentItemsCompanion.insert(
            returnId: 0,
            productId: productId,
            variantId: Value(variantId),
            quantity: 1,
            unitPriceCents: Decimal.fromInt(100),
            unitCostCents: Value(Decimal.fromInt(100)),
            totalCents: Decimal.fromInt(100),
          ),
        ],
        approvalService: approvalService,
      );
      final row = await adjDao.getPurchaseAdjReturnById(returnId);
      expect(row!.approvalStatus, ApprovalStatus.autoApproved);
      expect(row.approvalRequired, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // 3. Single chokepoint enforcement — pending must not post
  // ──────────────────────────────────────────────────────────────────────
  group('Phase 3.5 — ReturnPostingService rejects pending', () {
    test('postSaleAdjReturn while pending throws ApprovalRequired', () async {
      await approvalService.setThresholdCents(1);
      await approvalService.setRequireWhenNoInvoice(false);
      await approvalService.setRequireOnOverride(false);

      final returnId = await adjDao.createSaleAdjReturn(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SAR-P3-002',
          customerId: Value(customerId),
          currencyId: currencyId,
          totalCents: Decimal.fromInt(5000),
          refundMethod: const Value('cash'),
        ),
        [
          SaleReturnAdjustmentItemsCompanion.insert(
            sourceResolution: const Value('unverified'),
            sourceResolutionReason: const Value('test fixture'),
            returnId: 0,
            productId: productId,
            variantId: Value(variantId),
            quantity: 1,
            unitPriceCents: Decimal.fromInt(5000),
            totalCents: Decimal.fromInt(5000),
          ),
        ],
        approvalService: approvalService,
      );

      await expectLater(
        () => adjDao.postSaleAdjReturn(
          returnId,
          journalEntryService: journalService,
          allowOverHistory: true,
        ),
        throwsA(isA<ReturnApprovalRequiredException>()),
      );

      // Approve, then post must succeed.
      await adjDao.approveSaleAdjReturn(returnId, approvedBy: 7);
      await adjDao.postSaleAdjReturn(
        returnId,
        journalEntryService: journalService,
        userId: 7,
        allowOverHistory: true,
      );
      final posted = await adjDao.getSaleAdjReturnById(returnId);
      expect(posted!.status, 'posted');
      expect(posted.approvalStatus, ApprovalStatus.approved);

      // Audit fields populated by DAO post path.
      expect(posted.postedBy, 7);
      expect(posted.postedAt, isNotNull);
    });

    test('approving a non-pending return throws StateException', () async {
      await approvalService.setThresholdCents(0);
      await approvalService.setRequireWhenNoInvoice(false);
      await approvalService.setRequireOnOverride(false);

      final returnId = await adjDao.createPurchaseAdjReturn(
        PurchaseReturnAdjustmentsCompanion.insert(
          returnNumber: 'PAR-P3-002',
          supplierId: supplierId,
          currencyId: currencyId,
          totalCents: Decimal.fromInt(100),
        ),
        [
          PurchaseReturnAdjustmentItemsCompanion.insert(
            returnId: 0,
            productId: productId,
            variantId: Value(variantId),
            quantity: 1,
            unitPriceCents: Decimal.fromInt(100),
            unitCostCents: Value(Decimal.fromInt(100)),
            totalCents: Decimal.fromInt(100),
          ),
        ],
        approvalService: approvalService,
      );

      await expectLater(
        () => adjDao.approvePurchaseAdjReturn(returnId, approvedBy: 7),
        throwsA(isA<ReturnApprovalStateException>()),
      );
    });

    test('rejected return cannot be posted', () async {
      await approvalService.setThresholdCents(1);
      await approvalService.setRequireWhenNoInvoice(false);
      await approvalService.setRequireOnOverride(false);

      final returnId = await adjDao.createPurchaseAdjReturn(
        PurchaseReturnAdjustmentsCompanion.insert(
          returnNumber: 'PAR-P3-003',
          supplierId: supplierId,
          currencyId: currencyId,
          totalCents: Decimal.fromInt(5000),
        ),
        [
          PurchaseReturnAdjustmentItemsCompanion.insert(
            returnId: 0,
            productId: productId,
            variantId: Value(variantId),
            quantity: 1,
            unitPriceCents: Decimal.fromInt(5000),
            unitCostCents: Value(Decimal.fromInt(5000)),
            totalCents: Decimal.fromInt(5000),
          ),
        ],
        approvalService: approvalService,
      );
      await adjDao.rejectPurchaseAdjReturn(returnId, approvedBy: 7);

      await expectLater(
        () => adjDao.postPurchaseAdjReturn(
          returnId,
          journalEntryService: journalService,
          allowOverHistory: true,
        ),
        throwsA(isA<ReturnApprovalRequiredException>()),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // 4. Audit columns on void path
  // ──────────────────────────────────────────────────────────────────────
  group('Phase 3.6 — Void writes voidedBy/At/voidReason', () {
    test('void after post stamps audit trail', () async {
      await approvalService.setThresholdCents(0);
      await approvalService.setRequireWhenNoInvoice(false);
      await approvalService.setRequireOnOverride(false);

      final returnId = await adjDao.createSaleAdjReturn(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SAR-P3-VOID',
          customerId: Value(customerId),
          currencyId: currencyId,
          totalCents: Decimal.fromInt(500),
          refundMethod: const Value('cash'),
        ),
        [
          SaleReturnAdjustmentItemsCompanion.insert(
            sourceResolution: const Value('unverified'),
            sourceResolutionReason: const Value('test fixture'),
            returnId: 0,
            productId: productId,
            variantId: Value(variantId),
            quantity: 1,
            unitPriceCents: Decimal.fromInt(500),
            totalCents: Decimal.fromInt(500),
          ),
        ],
        approvalService: approvalService,
      );
      await adjDao.postSaleAdjReturn(
        returnId,
        journalEntryService: journalService,
        userId: 7,
        allowOverHistory: true,
      );
      await adjDao.voidSaleAdjReturn(
        returnId,
        journalEntryService: journalService,
        voidedBy: 7,
        voidReason: 'duplicate-entry',
      );
      final r = await adjDao.getSaleAdjReturnById(returnId);
      expect(r!.status, 'voided');
      expect(r.voidedBy, 7);
      expect(r.voidedAt, isNotNull);
      expect(r.voidReason, 'duplicate-entry');
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // 5. Reason-code lookup table — system protection + side filtering
  // ──────────────────────────────────────────────────────────────────────
  group('Phase 3.1/3.2 — return_reason_codes service', () {
    test('seeds standard system rows on first migration', () async {
      final all = await reasonCodeService.listAll();
      expect(all, isNotEmpty);
      expect(all.where((r) => r.isSystem).length, greaterThan(0));
    });

    test('side filter returns sale + both, excludes purchase-only', () async {
      final sale = await reasonCodeService.listActive(side: 'sale');
      expect(sale.every((r) => r.side == 'sale' || r.side == 'both'), isTrue);
    });

    test('delete on a system row throws SystemReasonCodeProtected', () async {
      final sys = (await reasonCodeService.listAll()).firstWhere(
        (r) => r.isSystem,
      );
      await expectLater(
        () => reasonCodeService.delete(sys.id),
        throwsA(isA<SystemReasonCodeProtectedException>()),
      );
    });

    test('operator-defined codes can be created and deactivated', () async {
      final id = await reasonCodeService.create(
        code: 'op_custom_1',
        labelEn: 'Custom reason',
        labelAr: 'سبب مخصص',
        side: 'both',
      );
      await reasonCodeService.setActive(id, false);
      final row = await reasonCodeService.findById(id);
      expect(row!.isActive, isFalse);
      expect(row.isSystem, isFalse);

      // Non-system rows can be deleted.
      await reasonCodeService.delete(id);
      expect(await reasonCodeService.findById(id), isNull);
    });
  });
}
